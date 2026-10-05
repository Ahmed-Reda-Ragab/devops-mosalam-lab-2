# trycloudflared-test — لينكات public مؤقتة للتجربة

كل ملف هنا بيقوّم pod فيه `cloudflared` بيفتح **Quick Tunnel**: لينك عشوائي على `trycloudflare.com`، من غير
حساب Cloudflare ومن غير public IP. الـ pod بيفتح اتصال **طالع** لـ Cloudflare، و Cloudflare يرجّع فيه طلبات
الزوار. نفس فكرة cloudflared اللي على cp1، بس جوه الكلستر، فلو cp1 وقع الـ pod يقوم على نود تانية.

> ⚠️ **ده للتجربة بس، ومش GitOps.** مفيش Argo Application بيقرا الفولدر ده، فبتطبّقه بـ `kubectl`
> وبتمسحه بـ `kubectl`. واللينك **public**: أي حد معاه اللينك يوصل للصفحة.

| الملف | بيوصل لإيه | الـ namespace | محتاج إيه |
|---|---|---|---|
| [01-cloudflared-argocd.yaml](01-cloudflared-argocd.yaml) | Argo CD UI | `argocd` | Argo CD متسطّب. **غيّر password الـ admin الأول** |
| [02-cloudflared-tasks.yaml](02-cloudflared-tasks.yaml) | Task Manager، عن طريق Traefik | `tasks-app` | التطبيق شغّال (doc 06/07) |
| [03-cloudflared-grafana.yaml](03-cloudflared-grafana.yaml) | Grafana | `monitoring` | مرحلة M2 في doc 08 |

**مفيش ملف لـ Prometheus ولا Alertmanager عن قصد:** الاتنين مالهمش login، واللي يوصل لـ Alertmanager
يقدر يعمل silence للـ alerts. استخدم الـ SSH tunnel اللي في doc 08.

---

## التشغيل

**🖥️ فين:** cp1، في نسخة الريبو

```bash
cd ~/devops-mosalam-lab-2 && git pull
kubectl apply -f k8s/trycloudflared-test/01-cloudflared-argocd.yaml
kubectl -n argocd rollout status deploy/cloudflared-argocd
```
**👀 ركّز على:** `successfully rolled out`. الـ readiness probe بيسأل `/ready` على port `2000`، وده مابيرجعش
`200` غير لما الـ tunnel يتوصّل بـ Cloudflare فعلًا. يعني `Ready` هنا معناها إن اللينك شغّال.

> لو كنت طبّقت النسخة القديمة من `01` (اللي كانت بتكلّم `https://…:443`)، الأمر ده بيعدّلها في مكانها.

### اللينك على Telegram

كل ملف فيه sidecar اسمه `telegram-notify` بيبعت اللينك على نفس الـ bot والـ chat بتوع Alertmanager، أول ما الـ
tunnel يبقى `Ready`. ولو الـ container عمل restart واللينك اتغيّر، بيبعت اللينك الجديد. اللينك بيوصل بالـ path
بتاعه (`/grafana/`، `/prometheus/`)، فتدوس عليه على طول. الـ block ده واحد في كل الملفات، والفرق الوحيد هو `LINK_PATH`.

الـ Secret مابيعدّيش من namespace لـ namespace، فمحتاج Secret اسمه `cloudflared-telegram` في كل namespace فيه
tunnel: `argocd` و `tasks-app` و `monitoring`. ده بيعمله [create-secrets.sh](../scripts/create-secrets.sh) من
نفس ملف `secrets/telegram_token` بتاع Alertmanager، **قبل** الـ apply:

```bash
bash k8s/scripts/create-secrets.sh argocd tasks-app monitoring
kubectl apply -f k8s/trycloudflared-test/02-cloudflared-tasks.yaml
kubectl -n tasks-app logs deploy/cloudflared-tasks -c telegram-notify -f
```
**👀 ركّز على:** `sent https://xxxx.trycloudflare.com/`. لو طلعت `telegram send failed` هتلاقي رد Telegram
جنبها (مثلًا `401 Unauthorized` معناها الـ token غلط). من غير الـ Secret الـ tunnel شغّال عادي، بس مفيش رسالة.
لباقي الملفات غيّر الـ namespace والـ deploy في أمر الـ logs (الجدول اللي تحت).

### اللينك من الـ logs

```bash
kubectl -n argocd logs deploy/cloudflared-argocd | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | head -1
```

| الملف | الـ namespace في أمر الـ logs | افتح |
|---|---|---|
| 01 | `-n argocd deploy/cloudflared-argocd` | `https://<link>/` |
| 02 | `-n tasks-app deploy/cloudflared-tasks` | `https://<link>/` |
| 03 | `-n monitoring deploy/cloudflared-grafana` | `https://<link>/grafana/` ← **لازم `/grafana/`** |

### اتأكد من cp1 نفسه

```bash
LINK=$(kubectl -n tasks-app logs deploy/cloudflared-tasks | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | head -1)
curl -s -o /dev/null -w '/          -> %{http_code}\n' "$LINK/"
curl -s -o /dev/null -w '/api/tasks -> %{http_code}\n' "$LINK/api/tasks"
```
**👀 ركّز على:** `200` و `200`. لو اللينك لسه جديد، ممكن DNS بتاع Cloudflare ياخد ثواني.

---

## لو حاجة مش شغّالة

| العَرَض | السبب | الحل |
|---|---|---|
| الـ pod مش `Ready`، وفي الـ logs `failed to request quick Tunnel` | الـ pods مش واصلة لـ `api.trycloudflare.com`، أو UDP/QUIC `7844` مقفول | `kubectl -n <ns> logs deploy/<name>`. cloudflared بيرجع لـ HTTP2 على TCP `7844` لوحده لو QUIC مقفول |
| `502 Bad Gateway` من Cloudflare | cloudflared مش قادر يوصل للـ Service | للـ 01: لازم `http://…:80` مش `https://…:443` (Argo شغّال `server.insecure`) |
| 02 بيرجّع `404` | الـ Host مش `tasks.el-programmer.click` | اتأكد من `--http-host-header` في الملف |
| 03 الصفحة بيضا أو `404` | فتحت `/` بدل `/grafana/` | Grafana شغّال على sub-path |
| 03 بيعلّق ومش بيوصل | الـ pod مش في namespace `monitoring` | الـ NetworkPolicy بتسمح لـ Grafana من جوه الـ namespace بس |
| Argo UI مش بيحدّث نفسه | Quick Tunnels مابتدعمش SSE (Server-Sent Events) | اعمل refresh للصفحة. ده قيد في Quick Tunnel، مش في Argo |
| اللينك اتغيّر | الـ pod عمل restart | كل restart = لينك جديد (بيتبعت على Telegram لوحده). لو عايز لينك ثابت محتاج Named Tunnel بحساب Cloudflare |
| مفيش رسالة على Telegram | الـ Secret `cloudflared-telegram` مش موجود في الـ namespace بتاع الـ pod، أو الـ token غلط | `kubectl -n <ns> logs deploy/<name> -c telegram-notify`، وبعدين `bash k8s/scripts/create-secrets.sh <ns>` |
| `apply` على 03-adminer بيطلع `field is immutable` | النسخة القديمة كان الـ selector بتاعها `app: cloudflared-grafana` بالغلط، والـ selector مابيتغيّرش | `kubectl -n monitoring delete deploy cloudflared-adminer` وبعدين `apply` تاني |

---

## التنضيف

```bash
kubectl delete -f k8s/trycloudflared-test/
```
بيمسح الـ Deployments التلاتة (اللي مش موجود بيطلع `NotFound`، وده عادي). اللينكات بتموت معاهم على طول.
الـ Secret `cloudflared-telegram` بيفضل موجود في التلات namespaces، لأنه من `create-secrets.sh` مش من الملفات دي. ده
مش بيضر، ولو عايز تمسحه:
`for ns in argocd tasks-app monitoring; do kubectl -n $ns delete secret cloudflared-telegram; done`
(المرة الجاية اللي تشغّل فيها `create-secrets.sh` هيعمله تاني).
