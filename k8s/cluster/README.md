# Cluster-level configuration (NOT synced by Argo CD)

Everything here is applied to the **nodes**, before Argo CD ever runs. It sits
outside `k8s/production/`, which is the only tree the Argo Applications watch.

Why it is not GitOps-managed: these files configure the thing that *runs* the
GitOps controller. Letting Argo CD manage the CNI it depends on means a bad
commit can sever Argo's own connection to the API server — and then nothing is
left to reconcile it back. Cluster bootstrap is a separate, deliberately manual
layer.

| File | Applied where | What it does |
|---|---|---|
| `rke2-config.yaml.example` | `/etc/rancher/rke2/config.yaml` on each node | RKE2 server config: `cni: none`, no kube-proxy, no bundled ingress, per-node addressing |
| `cilium-values.yaml` | `helm upgrade --install` | Cilium: eBPF, native routing, cluster-pool IPAM, MTU 1400, **Gateway API** |
| `gateway-api-crds.sh` | run once on a control-plane node | installs the Gateway API CRDs that Cilium needs but does not ship |

> The full narrative — every concept, why each choice was made, and how to
> rebuild all of it from nothing — is in **[`docs-rke2/`](../../docs-rke2/)**.

## This cluster, as it actually is

```
RKE2 v1.35.5+rke2r2 · 3 × control-plane + etcd · Cilium 1.19.4 (Helm)
cluster-cidr 10.42.0.0/16 · service-cidr 10.43.0.0/16 · cluster-dns 10.43.0.10

Node          eth0 NAT/1500     eth1 control/1400   eth2 pod-fabric/1400
rke2-k8s-01   192.168.32.20     172.16.0.20         172.17.0.19
rke2-k8s-02   192.168.32.21     172.16.0.21         172.17.0.20
rke2-k8s-03   192.168.32.22     172.16.0.22         172.17.0.21
```

## Enabling the Gateway API on the running cluster

Three commands, in this order. Nothing here is destructive, but read
`cilium-values.yaml` first — it lists exactly which values are new.

```bash
# 1) The CRDs. Cilium does NOT ship them, and without them its Gateway
#    controller starts, finds nothing, creates no GatewayClass, and logs no
#    error that points at the cause.
./gateway-api-crds.sh

# 2) Cilium, with gatewayAPI + hostNetwork + Hubble metrics added
helm repo add cilium https://helm.cilium.io/ && helm repo update
helm upgrade --install cilium cilium/cilium \
  --version 1.19.4 \
  --namespace kube-system \
  -f cilium-values.yaml
kubectl -n kube-system rollout status ds/cilium --timeout=5m

# 3) Verify BEFORE touching anything in k8s/production/
kubectl get gatewayclass cilium                    # want: Accepted=True
cilium status                                      # want: KubeProxyReplacement True
cilium config view | grep -E 'enable-gateway-api|enable-envoy|routing-mode|^mtu'
kubectl -n kube-system get ds | grep -E 'cilium|envoy'
```

> ⚠️ `helm upgrade` restarts the cilium DaemonSet. On a 3-node cluster that is a
> rolling restart of the datapath — existing connections survive, but do it
> outside a demo. `envoy.enabled: true` also adds a new `cilium-envoy`
> DaemonSet, so expect three new pods.

## Why Cilium is installed with Helm and not through RKE2

The RKE2 config says `cni: none`, so RKE2 deploys no CNI and there is no
`rke2-cilium` HelmChart object — which means **a `HelmChartConfig` would do
nothing**. Changes go through `helm upgrade` against `cilium-values.yaml`.

The trade-off, stated plainly: the RKE2-managed path (`cni: cilium` +
`HelmChartConfig`) survives a node rebuild automatically, because RKE2 reapplies
its bundled charts on every start. The Helm path does not — you have to re-run
the `helm upgrade`. In exchange you get full control of the chart version and
every value, which this setup needs: native routing, cluster-pool IPAM with a
/22 per node, three managed devices, and Gateway API are all a long way from the
bundled defaults.

`/root/01-cilium-values.yaml` on `rke2-k8s-01` is the original copy. **Stop
editing it** — use the file in this directory, or the two drift and nobody will
know which one the cluster is running.
