# Task Manager Application

A production-oriented full-stack application (FastAPI backend, MySQL, static
frontend) fronted by **Traefik** with **automatic HTTPS**, a **replicated
MySQL** data tier behind **ProxySQL**, a full **observability** stack, and
**Locust** load testing.

> **What changed since the first iteration:** Nginx was replaced by **Traefik**
> (auto TLS via Let's Encrypt), the single MySQL container became a
> **primary/replica pair behind ProxySQL** (read/write split), a **memcached**
> cache + **pagination** were added to the API, an **API key** now guards `/api`,
> and the stack was split into three independent Compose files under
> [compose/](compose/). See [docs/task2](docs/task2) for the narrative and
> [docs/شرح-عربي.md](docs/شرح-عربي.md) for the deep dive.

## Quick Start

### Prerequisites
- Docker + Docker Compose
- (For real certificates) a domain with an `A` record pointing at the host and
  ports `80`/`443` reachable. The default domain used here is
  `el-programmer.click`.

### Run everything (three stacks)

```bash
# 1) Copy env + secrets
cp .env.example .env
cp secrets/db_password.example          secrets/db_password
cp secrets/mysql_root_password.example  secrets/mysql_root_password
cp secrets/replication_password.example secrets/replication_password
cp secrets/grafana_admin_password.example secrets/grafana_admin_password
cp secrets/telegram_token.example       secrets/telegram_token

# 2) Create the shared networks once
docker network create public-network
docker network create db-network

# 3) Bring up the stacks (database first — the app connects to ProxySQL)
docker compose -f compose/docker-compose.database.yml   --env-file .env up -d --build
docker compose -f compose/docker-compose.apps.yml       --env-file .env up -d --build
docker compose -f compose/docker-compose.monitoring.yml --env-file .env up -d --build
```

> The root [docker-compose.yml](docker-compose.yml) and
> [docker-compose-traefik.yml](docker-compose-traefik.yml) are **legacy
> single-file** variants kept for reference. The current deployment is the three
> stacks in [compose/](compose/).

### Access

Traefik is the single public entrypoint on `80`/`443`; `80` redirects to `443`.
Everything else sits on internal networks and is reached by path (or subdomain):

| URL                                     | Serves                                   |
|-----------------------------------------|------------------------------------------|
| `https://el-programmer.click/`          | Frontend UI                              |
| `https://el-programmer.click/api/`      | Backend REST API (**needs `X-API-KEY`**) |
| `https://el-programmer.click/pro-api/`  | Same API, **no** auth (demo) → rewritten to `/api` |
| `https://el-programmer.click/grafana/`  | Grafana dashboards                       |
| `https://el-programmer.click/prometheus/` | Prometheus UI                          |
| `https://el-programmer.click/alertmanager/` | Alertmanager UI                      |
| `https://load.el-programmer.click/`     | Locust load-testing UI                   |

Each monitoring service also answers on a subdomain
(`grafana.…`, `prometheus.…`, `alertmanager.…`, `cadvisor.…`) that **redirects**
to its canonical path URL. Debug-only published ports: Prometheus `9090`,
Grafana `3100`, Adminer `8083`, Locust `8089`, ProxySQL `6033`.

## Architecture

Three independent Compose stacks over **shared, segmented Docker networks**.
Traefik is the only service exposed to the internet; every other service is
reachable through it or on an `internal: true` network.

```
                     Internet / host :80 → :443
                              │
                     ┌────────▼────────┐   public-network
                     │     Traefik     │   (edge · auto-TLS · routing · metrics)
                     └──┬───────────┬──┘
          private-network│           │monitoring-network
        ┌────────────────┼──┐        │
   ┌────▼─────┐   ┌───────▼──┐        │   ┌────────────────────────────────────┐
   │ frontend │   │ backend  │────────┼──▶│ OBSERVABILITY (monitoring-network)  │
   │ (static) │   │ (FastAPI)│        │   │ prometheus · grafana · loki         │
   └──────────┘   └────┬─────┘        └──▶│ promtail · alertmanager · cadvisor  │
                       │db-network         │ node-exporter · blackbox-exporter   │
        ┌──────────────▼───────────────┐   └────────────────────────────────────┘
        │  ProxySQL  (R/W split :6033) │
        │   ├── writes → mysql-primary │   ← GTID replication ──┐
        │   └── reads  → mysql-replica │◀───────────────────────┘
        │  + memcached · mysql-backup  │
        └──────────────────────────────┘   DATABASE stack (db-network)
```

**Network segmentation** (defence in depth):

| Network              | Exposed? | Members                                                        |
|----------------------|----------|----------------------------------------------------------------|
| `public-network`     | yes      | traefik, grafana, alertmanager, cadvisor, adminer              |
| `private-network`    | internal | traefik, frontend, backend, locust                             |
| `db-network`         | internal | backend, proxysql, mysql-primary, mysql-replica, memcached, backup |
| `monitoring-network` | internal | traefik, backend + all observability services                  |

## Services

### Application (`compose/docker-compose.apps.yml`)

| Service    | Image / Build         | Purpose                                                  |
|------------|-----------------------|----------------------------------------------------------|
| `traefik`  | `traefik:v3.7.7`      | Edge reverse proxy · Let's Encrypt TLS · routing · metrics |
| `frontend` | build `./frontend`    | Static UI (`nginx:1.27.2-alpine` + vanilla JS/CSS/HTML)  |
| `backend`  | build `./backend`     | FastAPI + SQLAlchemy REST API (paginated, cached)        |
| `locust`   | `locustio/locust:2.31.1` | Load-testing driver + web UI (`8089`)                 |

### Data (`compose/docker-compose.database.yml`)

| Service         | Image / Build        | Purpose                                            |
|-----------------|----------------------|----------------------------------------------------|
| `mysql-primary` | `mysql:8.0`          | Read/write source of truth (GTID binlog)           |
| `mysql-replica` | `mysql:8.0`          | Read-only replica (GTID replication)               |
| `proxysql`      | build `./proxysql`   | Single SQL entrypoint (`:6033`), routes reads→replica / writes→primary |
| `mysql-backup`  | build `./backup-mysql` | Nightly `mysqldump` + 30-day retention + restore  |
| `adminer`       | `adminer:4.8.1`      | Web DB UI (`8083`)                                 |
| `memcached`     | `memcached:1.6-alpine` | Application cache (60s task-list cache)           |

See [compose/README.md](compose/README.md) for the database stack details
(replication, ProxySQL routing, backup/restore, verification commands).

### Observability (`compose/docker-compose.monitoring.yml`)

| Service             | Image                          | Purpose                                   |
|---------------------|--------------------------------|-------------------------------------------|
| `prometheus`        | `prom/prometheus:v2.54.1`      | Metrics scraping, storage & alert rules   |
| `grafana`           | `grafana/grafana:11.2.0`       | Dashboards (metrics + logs)               |
| `loki`              | `grafana/loki:3.2.0`           | Log aggregation store                     |
| `promtail`          | `grafana/promtail:3.2.0`       | Ships container logs → Loki               |
| `alertmanager`      | `prom/alertmanager:v0.27.0`    | Routes alerts (Telegram)                  |
| `cadvisor`          | `cadvisor:v0.49.1`             | Per-container resource metrics            |
| `node-exporter`     | `prom/node-exporter:v1.8.2`    | Host-level metrics (CPU/mem/disk)         |
| `blackbox-exporter` | `prom/blackbox-exporter:v0.26.0` | External probing + **SSL cert expiry** metric |

**Operational conventions** on every service: `restart: unless-stopped`,
`mem_limit`/`cpus` caps, `healthcheck` probes, and size-based log rotation.

## Security

- **TLS everywhere** — Traefik obtains and renews Let's Encrypt certs (ACME
  HTTP-01); HTTP is redirected to HTTPS.
- **API key** — `/api` requires an `X-API-KEY` header (Traefik plugin); a
  missing/unknown key is rejected with `403`. Configured in
  [traefik/dynamic/api-key.yml](traefik/dynamic/api-key.yml).
- **Edge middlewares** ([traefik/dynamic/](traefik/dynamic/)) — rate limiting,
  request body-size limit, CORS, compression, security headers (HSTS, anti
  clickjacking / MIME-sniffing), IP allow-list on the dashboard, and TLS 1.2+
  defaults.
- **Docker secrets** — passwords/tokens are files under `./secrets/*`
  (git-ignored), mounted at `/run/secrets/*` — never env vars.

## Project structure

```
.
├── compose/                    # ── Current deployment: three stacks ─────────
│   ├── docker-compose.apps.yml         #   Traefik + backend + frontend + locust
│   ├── docker-compose.database.yml     #   MySQL primary/replica + ProxySQL + backup + memcached
│   ├── docker-compose.monitoring.yml   #   Prometheus/Grafana/Loki/… + blackbox
│   └── README.md                       #   Database stack deep dive
│
├── docker-compose.yml          # legacy single-file stack (reference)
├── docker-compose-traefik.yml  # legacy single-file Traefik stack (reference)
│
├── backend/                    # FastAPI app (routes, crud, cache, models, schemas, migrations, tests)
├── frontend/                   # Static UI (index.html · style.css · app.js · nginx.conf)
│
├── traefik/                    # ── Edge proxy config ────────────────────────
│   ├── traefik.yml · acme.json         #   (git-ignored)
│   └── dynamic/                        #   api-key · ip-whitelist · middlewares · security · tls
│
├── mysql/                      # primary/ + replica/  (my.cnf + init scripts for GTID replication)
├── proxysql/                   # Dockerfile + init.sql + startup.sh (R/W split config)
├── backup-mysql/               # Dockerfile + cron + backup.sh / restore.sh / cleanup.sh
│
├── prometheus/                 # prometheus.yml · alerts.yml · blackbox.yml
├── alertmanager/ · promtail/ · grafana/     # observability configs + dashboards
│
├── locust/                     # locustfile.py · locustfile_web.py · run_locust.ps1
├── scripts/                    # backup.sh · restore.sh · verify-restore.sh (host-side)
├── secrets/                    # Docker secrets (*.example tracked, real values ignored)
│
├── docs/                       # task1 · task2 · شرح-عربي.md · شهادات-SSL-TLS.md
├── SCALING.md                  # Maturity assessment + scaling roadmap
└── .github/workflows/ci.yml    # CI: lint + test → build + Trivy scan → push
```

## Features

### Backend
- RESTful CRUD for tasks
- **Pagination** (`page` / `limit`, capped at 100/page) with `total`/`pages` metadata
- **memcached caching** of the task list (60s TTL, invalidated on writes;
  response `source` shows `cache` vs `db`, `container` shows which replica served)
- Health-check endpoint · SQLAlchemy 2.x ORM · Pydantic validation
- Request/error logging · Alembic migrations · Swagger docs

### Frontend
- Task listing with create / edit / delete and status management
- Responsive, no external framework, configurable backend URL + API key field

## Environment configuration

Non-secret settings live in `.env` (copy from the template):
```bash
cp .env.example .env
```
```env
DB_HOST=proxysql      # app talks to ProxySQL, not MySQL directly
DB_PORT=6033
DB_DATABASE=appdb
DB_USERNAME=appuser
```
Passwords and tokens are **not** stored here — they are Docker secrets under
`./secrets/*` (git-ignored).

## API reference

### List tasks (paginated)
```http
GET /api/tasks?page=1&limit=10
X-API-KEY: <key>
```
Returns `{ tasks, pagination: { page, limit, total, pages }, source, container }`.

### Get / create / update / delete
```http
GET    /api/tasks/{id}
POST   /api/tasks           { "name": "...", "description": "...", "status": "pending" }
PUT    /api/tasks/{id}      { "name": "...", "status": "completed" }
DELETE /api/tasks/{id}
GET    /health
```
All `/api/*` calls require the `X-API-KEY` header (or use the unauthenticated
`/pro-api/*` demo prefix).

## Load testing

```bash
# via the Compose service (UI on :8089, or load.el-programmer.click)
docker compose -f compose/docker-compose.apps.yml up -d locust

# or locally on Windows
cd locust && ./run_locust.ps1
```

## Development

```bash
# Backend
cd backend && pip install -r requirements.txt
python -m uvicorn app.main:app --reload

# Frontend
cd frontend && python -m http.server 8080   # then http://localhost:8080
```

## Documentation

- [docs/task1](docs/task1) — first iteration (single node + Nginx + monitoring)
- [docs/task2](docs/task2) — this iteration (Traefik + TLS + replication + load testing)
- [docs/شرح-عربي.md](docs/شرح-عربي.md) — domain, ACME, monitoring & blackbox deep dive
- [docs/شهادات-SSL-TLS.md](docs/شهادات-SSL-TLS.md) — TLS/SSL certificate notes
- [compose/README.md](compose/README.md) — database stack
- [SCALING.md](SCALING.md) — maturity assessment & scaling roadmap

## Notes

- Database schema is initialised from `backend/init.sql` on the primary and
  **replicates** to the replica on first boot.
- The app is **stateless** (state lives in MySQL + memcached), so the `backend`
  service can be scaled to multiple replicas behind Traefik.
- All containers restart automatically on failure; secrets are read from
  `/run/secrets/*`.
