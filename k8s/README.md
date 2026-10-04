# Kubernetes platform — RKE2 + Cilium + Gateway API + Argo CD

Plain Kubernetes manifests for the Task Manager stack, synced by **Argo CD**,
routed by the **Gateway API** implementation built into **Cilium**, on a 3-node
**RKE2** cluster.

This replaces the three Compose files under [compose/](../compose/); those stay
in the repo as the reference for what each object was translated *from*, and
every manifest here carries a comment naming its Compose counterpart.

No Kustomize, no Helm templating for the workloads — one directory per
component, one file per object, readable in a pull request diff.

---

## 1. What lives where

```
k8s/
├── cluster/                         ← applied to the NODES, never by Argo CD
│   ├── rke2-config.yaml.example     /etc/rancher/rke2/config.yaml reference
│   ├── cilium-helmchartconfig.yaml  eBPF, native routing, MTU 1400, Gateway API
│   └── gateway-api-crds.sh          installs the Gateway API CRDs
│
├── argocd/                          ← applied by hand, ONCE
│   ├── 00-appproject.yaml           AppProject: the blast-radius fence
│   ├── 01-root-app.yaml             app-of-apps root
│   ├── applications/                namespaces, database, apps — what the root syncs
│   ├── later/                       platform, gateway, monitoring — NOT synced yet
│   └── addons/cert-manager.yaml     OPTIONAL: cert-manager as an Argo Application
│
│   On the lab cluster (Traefik Gateway, no cert-manager) the runbook is
│   rke2-cilium-private-cloud/docs/07-ArgoCD-GitOps.md.
│
├── production/
│   ├── namespaces/      wave -2   gateway, tasks-app, tasks-db, monitoring
│   ├── platform/        wave -1   cert-manager ClusterIssuers
│   ├── gateway/         wave  0   the shared Gateway, its cert, :80→:443
│   ├── database/        wave  1   MySQL, ProxySQL, memcached, Adminer, backup
│   ├── apps/            wave  2   backend, frontend, Locust + HTTPRoutes
│   └── monitoring/      wave  3   Prometheus, Grafana, Loki, Tempo, OTel, KSM
└── scripts/
    ├── render-dashboards.sh         regenerates the Grafana dashboard ConfigMap
    └── set-image-repo.sh            repoints the images at another registry
```

`k8s/cluster/` is deliberately outside `production/`, which is the only tree the
Argo Applications watch. Letting Argo CD manage the CNI it depends on means a bad
commit can sever Argo's own connection to the API server, and then nothing can
reconcile it back. Cluster bootstrap is a separate, deliberately manual layer.

Adding a `staging` environment = `cp -r production staging`, edit the hostnames,
replica counts and namespaces, and add six more Applications. That duplication is
the deliberate trade-off of plain YAML over overlays: more bytes, zero
indirection.

### Namespaces replace the Compose networks

| Compose network | Kubernetes | Isolated by |
|---|---|---|
| `public-network` | namespace `gateway` (the shared Gateway) | it *is* the edge |
| `private-network` (`internal: true`) | namespace `tasks-app` | `apps/networkpolicy.yaml` |
| `db-network` | namespace `tasks-db` | `database/networkpolicy.yaml` |
| `monitoring-network` (`internal: true`) | namespace `monitoring` | `monitoring/networkpolicy.yaml` |

Your CNI is Cilium, so the NetworkPolicies are genuinely enforced. Read the
header of [`apps/networkpolicy.yaml`](production/apps/networkpolicy.yaml) before
trusting them though — Gateway traffic arrives as Cilium's `reserved:host`
identity, which **no Kubernetes NetworkPolicy selector can name**, so those
policies cover pod-to-pod only. Constraining the Gateway needs a
`CiliumNetworkPolicy`.

---

## 2. Why Gateway API and not Ingress

Ingress has exactly one extension point: annotations. Everything Traefik did —
rate limits, header rewriting, redirects, auth — had to be smuggled through
vendor-prefixed annotation strings the API server cannot validate. Three things
that concretely bit the Ingress version of this repo:

| Problem with Ingress | What Gateway API does |
|---|---|
| **Annotations are per-Ingress, not per-path.** `/api` needed a rate limit and an auth gate, `/pro-api` deliberately needed neither plus a rewrite, `/` needed a different backend → **three Ingress objects** for one hostname, each with its own duplicated `tls:` block. | Filters live on the **rule**. One HTTPRoute, three rules. |
| **No cross-namespace TLS.** An Ingress can only reference a Secret in its own namespace, and Secrets do not cross namespaces → **two Let's Encrypt certificates** for `el-programmer.click`, one in `tasks-app` and one in `monitoring`, both counting against the 5-duplicates-per-week limit. | TLS terminates at the Gateway. **One** certificate, in `gateway`. |
| **No role separation.** Anyone who could create an Ingress could claim any hostname and set any annotation. | Platform owns the Gateway, its TLS and `allowedRoutes`. Teams own only HTTPRoutes. |

Concrete result in this repo: **11 Ingress objects → 8 HTTPRoutes**, and
**3 Certificates → 1**.

Two things that were annotations became **core, validated** resources:

- `ssl-redirect` on every Ingress → one `RequestRedirect` filter
  ([`gateway/httproute-https-redirect.yaml`](production/gateway/httproute-https-redirect.yaml))
- the subdomain redirects, which on ingress-nginx needed a raw
  `configuration-snippet` containing `return 302 ... $request_uri` **and** a
  cluster-wide `allow-snippet-annotations=true` flag, → `RequestRedirect` with
  `ReplacePrefixMatch`
  ([`monitoring/routes/httproute-subdomain-redirects.yaml`](production/monitoring/routes/httproute-subdomain-redirects.yaml))

### Why Cilium is the Gateway controller

The task already mandates Cilium with `kube-proxy` replacement. Cilium's Gateway
API controller **requires exactly that** (`kubeProxyReplacement=true` +
`l7Proxy=true`), so the Gateway costs nothing extra: no second controller
Deployment, no separate Envoy to operate, one fewer thing to patch.

It is also the only choice that ages well here. ingress-nginx reached
**end-of-life in March 2026**; RKE2 v1.36 replaced it with Traefik as the bundled
default and v1.37 removes it entirely.

### Multi-tenant routing

`allowedRoutes.namespaces.from: Selector` on the Gateway's listeners is the
tenancy boundary. A namespace joins the platform by carrying

```yaml
gateway.el-programmer.click/access: "true"
```

Namespaces are cluster-scoped, so only a platform admin can set it. A team that
creates an HTTPRoute in an unlabelled namespace gets a clear
`NotAllowedByListeners` condition **on their own object** — not a silent failure,
and not access. To scale further, give each tenant its own Gateway on its own
hostname in its own namespace: they then get their own TLS and listener config
with no ability to affect a neighbour. Ingress cannot express that at all.

---

## 3. Cluster prerequisites

Your cluster is already up (3× control-plane+etcd, RKE2 v1.35, Cilium running).
What still has to be true before the first Argo sync:

| # | Thing | Check | Fix |
|---|---|---|---|
| 1 | **Gateway API CRDs** installed | `kubectl get crd \| grep gateway.networking` | `./k8s/cluster/gateway-api-crds.sh` |
| 2 | **Cilium `gatewayAPI.enabled`** | `cilium config view \| grep enable-gateway-api` | `kubectl apply -f k8s/cluster/cilium-helmchartconfig.yaml` |
| 3 | **A `cilium` GatewayClass** exists and is Accepted | `kubectl get gatewayclass cilium` | follows from 1 + 2 |
| 4 | **kube-proxy replacement** on | `cilium status \| grep KubeProxyReplacement` | `disable-kube-proxy: true` + the Helm value |
| 5 | **MTU is 1400** | `cilium config view \| grep -w mtu` | the Helm value; see below |
| 6 | **bundled ingress controller disabled** | `kubectl -n kube-system get ds,deploy \| grep -i ingress` | `disable: [rke2-ingress-nginx]` in the RKE2 config |
| 7 | **cert-manager** installed **with the Gateway API feature gate** | `kubectl -n cert-manager get deploy cert-manager -o yaml \| grep feature-gates` | `--feature-gates=ExperimentalGatewayAPISupport=true` |
| 8 | **Argo CD** installed | `kubectl -n argocd get pods` | `kubectl apply -n argocd -f .../argo-cd/stable/manifests/install.yaml` |
| 9 | A default **StorageClass** | `kubectl get sc` | ⚠️ **not done yet** — see §7 |

Three of these are worth spelling out because they fail in confusing ways.

**(1) and (3) — the CRDs.** Cilium does not ship the Gateway API CRDs. Without
them its Gateway controller stays idle: no GatewayClass appears, and there is no
error anywhere that points at the cause. This is the single most common reason a
Cilium Gateway "does nothing".

**(5) — MTU 1400.** If Cilium guesses 1500 on a 1400 underlay, every full-size
packet is dropped or fragmented at the first hop. The symptom is the worst kind:
small requests work, large responses hang. TLS handshakes complete and *then* the
connection stalls mid-body. You will blame the app.

**(7) — the cert-manager feature gate.** `ExperimentalGatewayAPISupport` is
**off** by default. The ClusterIssuers in
[`platform/cluster-issuer.yaml`](production/platform/cluster-issuer.yaml) use the
`gatewayHTTPRoute` HTTP-01 solver, and without the gate cert-manager silently
never solves a challenge.

### How external traffic reaches the Gateway

`gatewayAPI.hostNetwork.enabled: true` in the Cilium values, so Envoy binds the
Gateway's ports **directly on every node**. That is the right choice for this lab:
the external IP is DNAT'd to the node addresses, so traffic arrives at
`<nodeIP>:443` and something has to be listening there. A LoadBalancer IP from
LB-IPAM would never receive it, because the DNAT targets the node, not the LB IP.

Consequence: `:80` and `:443` are now occupied on all three nodes — which is the
other reason the bundled `rke2-ingress-nginx` must be off.

If your lab instead routes the external IP into the nodes' own L2 segment, set
`hostNetwork.enabled: false` and add a `CiliumLoadBalancerIPPool` plus a
`CiliumL2AnnouncementPolicy`.

---

## 4. Bootstrap

```bash
# 0) DNS — point all six names at the external IP the lab gave you
#      el-programmer.click
#      load.el-programmer.click
#      adminer.el-programmer.click
#      grafana.el-programmer.click
#      prometheus.el-programmer.click
#      alertmanager.el-programmer.click

# 1) Prerequisites from §3
./k8s/cluster/gateway-api-crds.sh
kubectl apply -f k8s/cluster/cilium-helmchartconfig.yaml
kubectl -n kube-system rollout status ds/cilium --timeout=5m
kubectl get gatewayclass cilium          # must be Accepted=True

# 2) Namespaces must exist before their Secrets do, and Argo has not run yet
kubectl create ns gateway tasks-app tasks-db monitoring

# 3) Secrets — NEVER in git as plaintext. See §5.
kubectl -n tasks-db create secret generic mysql-secrets \
  --from-file=mysql_root_password=secrets/mysql_root_password \
  --from-file=replication_password=secrets/replication_password \
  --from-file=db_password=secrets/db_password \
  --from-literal=monitor_password="$(openssl rand -hex 16)"

kubectl -n tasks-app create secret generic backend-secrets \
  --from-file=db_password=secrets/db_password

kubectl -n monitoring create secret generic grafana-secrets \
  --from-file=grafana_admin_password=secrets/grafana_admin_password
kubectl -n monitoring create secret generic alertmanager-secrets \
  --from-file=telegram_token=secrets/telegram_token

# 4) Hand it to Argo CD. These two commands are the last kubectl you run.
kubectl apply -f k8s/argocd/00-appproject.yaml
kubectl apply -f k8s/argocd/01-root-app.yaml

# 5) Watch
kubectl -n argocd get applications -w
```

### Use the staging ACME issuer first

`letsencrypt-prod` allows **5 duplicate certificates per domain per week**. One
wrong DNS record burns through that in an afternoon and then you wait. Deploy
with staging, confirm the challenge completes, then switch:

```bash
# in gateway/certificate.yaml:  issuerRef.name: letsencrypt-staging
# commit, let Argo sync, then:
kubectl -n gateway get certificate,challenge,httproute
#   a cm-acme-http-solver-* HTTPRoute appears during validation, then disappears
# once Ready=True, flip back to letsencrypt-prod, commit, and force a reissue:
kubectl -n gateway delete secret el-programmer-tls
```

> **Does the blanket `:80 → :443` redirect break HTTP-01?** No. cert-manager's
> solver HTTPRoute matches the specific path
> `/.well-known/acme-challenge/<token>`, and Gateway API orders matches across
> *all* routes on a listener by specificity. The redirect rule has no path match
> at all (defaulting to `PathPrefix: /`, the least specific possible), so the
> challenge always wins while it exists. Verify, don't trust — watch for the
> solver route above.

---

## 5. Secrets

The `*.yaml.example` files are **templates, not manifests**. Argo CD only picks up
`*.yaml` / `*.yml` / `*.json`, and each Application additionally sets
`directory.exclude: "*.example"`, so they are never synced.

Creating them with `kubectl create secret` (§4) works, but it is not GitOps: the
values live in one person's shell history and nowhere else, and a cluster rebuild
needs a human who remembers. Pick one of these instead:

| Approach | What goes in git | Good when |
|---|---|---|
| **Sealed Secrets** | the sealed ciphertext | simplest real answer; the controller's private key is the only thing that opens it |
| **External Secrets Operator** | an `ExternalSecret` pointing at Vault / a cloud secret manager | you already have one; also fixes the duplicated `db_password` below |
| **SOPS + age** | the encrypted YAML | you want a plain file you can diff |

> `db_password` is needed in **both** `tasks-db/mysql-secrets` and
> `tasks-app/backend-secrets` — Secrets do not cross namespaces. If they drift,
> ProxySQL rejects the backend with `Access denied for user 'appuser'`.

---

## 6. How a deploy happens

```
git push (backend/ or frontend/)
   │
   ├─► CI: build-and-push-backend / -frontend   → Docker Hub :latest and :<sha>
   │
   └─► CI: bump-manifests
          rewrites  image: …/task-manager-backend:<sha>
          in k8s/production/apps/*/deployment.yaml
          commits  "chore(deploy): pin app images to <sha> [skip ci]"
                   │
                   ▼
            Argo CD sees the new revision on main
                   │
                   ▼
            rolling update, maxUnavailable: 0
```

CI holds **no** cluster credentials and never runs `kubectl`. It writes a commit;
Argo CD is the only thing with access to the cluster. Which means:

- `git log --oneline -- k8s/production/apps` **is** the deployment history
- a rollback is `git revert <bump-commit>` — no kubectl, no Argo UI
- the manifests always name an immutable `:<sha>` tag, never `:latest`

### Sync waves

| Wave | Application | Reason for the position |
|---|---|---|
| -2 | namespaces | everything targets one, and the Gateway's `allowedRoutes` selector reads their labels |
| -1 | platform | the ClusterIssuers must exist before the Certificate |
| 0 | gateway | HTTPRoutes in later waves attach to it |
| 1 | database | apps connect to it; Compose enforced this with "start the database stack first" |
| 2 | apps | the thing users see |
| 3 | monitoring | it observes the other three |

`prune: false` on **namespaces, gateway, database and monitoring** — those hold
PVCs, hostnames and a private key, and a deleted file should not be able to
destroy them. `prune: true` on apps and platform, which are stateless.

Two `ignoreDifferences` entries are load-bearing:

- **`Deployment/backend` `/spec/replicas`** — the HPA owns it at runtime. Git says
  3; the moment the HPA scales to 7, Argo sees drift and `selfHeal` scales it back,
  and the HPA scales up again. Without this the two controllers fight in a loop
  for as long as there is load, and the pod churn looks exactly like a crash.
- **`Gateway` `/spec/addresses`** — Cilium writes the assigned address back onto
  the object, which Argo would strip on every refresh, making the Gateway flap.

---

## 7. Not done yet — the rest of task 4

This tree covers the cluster-facing parts of items 3, 4, 5 and part of 8. What is
still open, in the order I would do it:

| Item | Status | What is needed |
|---|---|---|
| **7 — Storage layer** | ⚠️ PVCs exist, no provisioner | Install **Longhorn**. Not `local-path`: the task tests **node failure**, and local-path keeps data on one node, so that test cannot pass. Then set `storageClassName: longhorn` on the six PVC/volumeClaimTemplates (they currently rely on a cluster default). |
| **6 — Argo Rollouts** | ❌ nothing yet | Argo Rollouts + the `argoproj-labs/gatewayAPI` traffic-router plugin, which lists Cilium as supported and drives `backendRefs[].weight` on an HTTPRoute. Convert the backend Deployment to a `Rollout` with canary steps 10/25/50/100, add stable + canary Services, and an `AnalysisTemplate` querying the Prometheus already in this repo so a bad canary **auto-aborts** on the existing RED metrics instead of needing a human. Blue/Green for the frontend. |
| **8 — CI PR checks** | ⚠️ build + bump only | A PR workflow: `kubeconform` against the Gateway API + Cilium schemas, `yamllint`, and `argocd app diff` posted as a comment. |
| **9 — Failure tests** | ❌ | Drain a node, kill a pod, push a broken image, roll back. Document what happened. |
| **10 — Diagrams** | ⚠️ text only | Architecture, network (3 NICs), deploy flow, GitOps flow, rollout strategy. |

### Capabilities lost in the Ingress → Gateway API move

All three are real, and all three are consequences of choosing Cilium as the
controller rather than Envoy Gateway:

1. **Rate limiting is gone.** `nginx.ingress.kubernetes.io/limit-rps: "10"` had no
   Gateway API equivalent — core has no rate-limit filter and Cilium has none
   either. `/api` is currently **unthrottled**. Options: `slowapi` in the FastAPI
   app (which can also limit *per API key*, not just per IP), or swap to **Envoy
   Gateway**, whose `BackendTrafficPolicy` does global rate limiting.
2. **The API-key gate moved to the pod.** Gateway API has no auth filter, so it is
   now an L7 `CiliumNetworkPolicy` —
   [`apps/routes/ciliumnetworkpolicy-api-key.yaml.optional`](production/apps/routes/ciliumnetworkpolicy-api-key.yaml.optional).
   **It ships disabled**, because a CNP that selects an endpoint makes it
   default-deny, and if my allow-list is wrong in any detail the backend stops
   answering its own liveness probe. That file has the three-step enable
   procedure and the one-command rollback. Read it before enabling.

   The key is **still plaintext in git** either way — it just moved files. The end
   state is an `API_KEY` env var from `backend-secrets` checked by a FastAPI
   dependency. **Rotate this key.**
3. **The edge no longer starts the trace.** Traefik opened the root span and
   injected W3C `traceparent`, so one trace covered TLS termination + middlewares
   + the FastAPI handler + SQL. ingress-nginx could do the same
   (`enable-opentelemetry`). Cilium's Gateway Envoy exposes no tracing toggle, so
   the FastAPI span is now the trace **root** and proxy-side latency is not in the
   waterfall. Hubble's HTTP flow metrics still cover it in Prometheus. Getting it
   back needs a `CiliumEnvoyConfig` with a tracing filter, or Envoy Gateway.

> Envoy Gateway would fix all three (rate limiting via `BackendTrafficPolicy`,
> API-key auth from a **Secret** via `SecurityPolicy`, and first-class OTel) at
> the cost of a second controller on top of Cilium. Worth revisiting if the
> plaintext key or the missing throttle turns out to matter.

Also still open from before: Adminer, Prometheus, Alertmanager and Locust are
publicly reachable with **no authentication** (exactly as in the Compose stack),
and backups live on a PVC in the same cluster.

---

## 8. Verify

```bash
# --- the Gateway itself ---
kubectl get gatewayclass cilium
kubectl -n gateway get gateway main -o wide
kubectl -n gateway describe gateway main | grep -A5 -E 'Conditions|Listeners'
#   want: Accepted=True, Programmed=True, and attachedRoutes > 0 per listener

# every route across every namespace, and whether it was accepted
kubectl get httproute -A
kubectl -n tasks-app describe httproute task-manager | grep -A8 'Parents:'
#   ResolvedRefs=True and Accepted=True. "NotAllowedByListeners" means the
#   namespace is missing gateway.el-programmer.click/access=true.

# --- TLS ---
kubectl -n gateway get certificate,challenge
echo | openssl s_client -connect el-programmer.click:443 \
  -servername el-programmer.click 2>/dev/null | openssl x509 -noout -dates -subject

# --- routing, end to end ---
curl -sI  https://el-programmer.click/            | head -1   # frontend  200
curl -sI  https://el-programmer.click/grafana/    | head -1   # grafana   200/302
curl -sI  http://el-programmer.click/             | head -1   # 301 to https
curl -sI  https://grafana.el-programmer.click/d/x | head -3   # 302, path preserved
curl -o /dev/null -w 'pro-api -> %{http_code}\n' https://el-programmer.click/pro-api/tasks

# --- Cilium datapath ---
cilium status
cilium config view | grep -E 'enable-gateway-api|kube-proxy-replacement|routing-mode|^mtu'
kubectl -n kube-system exec ds/cilium -- cilium-dbg service list | head
hubble observe --namespace tasks-app --type l7 -f     # live L7 flows

# --- data tier: is replication actually running? ---
kubectl -n tasks-db exec sts/mysql-replica -- \
  sh -c 'mysql -uroot -p"$(cat /run/secrets/mysql_root_password)" \
         -e "SHOW REPLICA STATUS\G"' | grep -E 'Running|Seconds_Behind|Last_Error'

# --- monitoring: every target up, every rule valid? ---
kubectl -n monitoring port-forward svc/prometheus 9090:9090
#   http://localhost:9090/prometheus/targets   → all up
#   http://localhost:9090/prometheus/rules     → every group "ok"
```

### When something is wrong

| Symptom | Look at |
|---|---|
| no `cilium` GatewayClass | Gateway API CRDs not installed, or `gatewayAPI.enabled` not set |
| Gateway `Programmed=False` | `kubectl -n gateway describe gateway main`; usually no address (LB-IPAM missing and `hostNetwork` off) |
| HTTPRoute `NotAllowedByListeners` | its namespace lacks `gateway.el-programmer.click/access: "true"` |
| HTTPRoute `ResolvedRefs=False` | the backend Service name/port is wrong, or it is cross-namespace without a `ReferenceGrant` |
| Certificate stuck `Ready=False` | `kubectl -n gateway get challenge`; DNS not at the node IPs, `:80` unreachable, or cert-manager's Gateway feature gate is off |
| 404 from the Gateway on a path that should work | a more specific rule is matching first — `kubectl -n <ns> get httproute -o yaml` and compare path specificity |
| `:80`/`:443` already in use on a node | `rke2-ingress-nginx` is still enabled |
| TLS handshake OK then the connection hangs | **MTU.** `cilium config view \| grep -w mtu` must be 1400 |
| **Loki has no logs at all** | the Promtail `containerd` hostPath. RKE2 roots it at `/var/lib/rancher/rke2/agent/containerd`, not `/var/lib/containerd`; `/var/log/pods` holds symlinks into it |
| backend `Access denied for user 'appuser'` | `db_password` differs between the two namespaces' Secrets |
| `/api` returns 200 without a key | expected — the L7 policy ships disabled. See §7 |
| backend pods flapping between 3 and N | the `ignoreDifferences` on `/spec/replicas` is missing; Argo and the HPA are fighting |
| Grafana "trace → logs" finds nothing | Promtail's `service` relabel must match `OTEL_SERVICE_NAME` |
| Service Map / span metrics empty | Prometheus needs `--web.enable-remote-write-receiver`; check `TempoMetricsGeneratorWriteFailing` |

---

## Sources

- [Cilium — Gateway API prerequisites](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/)
- [Cilium — Gateway API traffic splitting](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/splitting/)
- [RKE2 — Network options (Cilium, HelmChartConfig)](https://docs.rke2.io/networking/basic_network_options)
- [RKE2 — Networking services (bundled ingress controller)](https://docs.rke2.io/networking/networking_services)
- [Argo Rollouts — traffic router plugins](https://argoproj.github.io/argo-rollouts/features/traffic-management/plugins/)
- [Argo Rollouts Gateway API plugin](https://rollouts-plugin-trafficrouter-gatewayapi.readthedocs.io/)
