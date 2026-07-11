# Task Manager Application

A production-ready full-stack application with FastAPI backend, MySQL database, and a lightweight frontend.

## Quick Start

### Prerequisites
- Docker
- Docker Compose

### Run Everything
```bash
docker compose up --build
```

### Access

All traffic enters through the **Nginx reverse proxy** on port `80` — the app
and monitoring services are *not* published directly (they sit on internal
networks) and are reached by path prefix:

| URL                          | Serves                     |
|------------------------------|----------------------------|
| http://localhost/            | Frontend UI                |
| http://localhost/api/        | Backend REST API           |
| http://localhost/grafana/    | Grafana dashboards         |
| http://localhost/prometheus/ | Prometheus UI              |
| http://localhost/alertmanager/ | Alertmanager UI          |

Directly published ports (for debugging only): Grafana `3100`, Prometheus
`9090`, cAdvisor `8082`.

## Architecture

Twelve services split across **four isolated Docker networks**. Nginx is the
single public entrypoint; every other service is reachable only through it or
on an internal (`internal: true`) network — nothing else is exposed to the host.

```
                         Internet / host :80
                                 │
                        ┌────────▼────────┐   public-network
                        │      nginx      │   (edge reverse proxy)
                        └───┬────────┬────┘
             private-network│        │monitoring-network
              ┌─────────────┼─┐      │
        ┌─────▼────┐   ┌─────▼────┐  │   ┌──────────────────────────────┐
        │ frontend │   │ backend  │──┼──▶│  OBSERVABILITY (monitoring)  │
        │ (static) │   │ (FastAPI)│  │   │  prometheus · grafana · loki │
        └──────────┘   └─────┬────┘  └──▶│  promtail · alertmanager     │
                    db-network│          │  cadvisor · node-exporter    │
                        ┌─────▼────┐      └──────────────────────────────┘
                        │    db    │  MySQL 8 (data tier, isolated)
                        └──────────┘
```

**Network segmentation** (defence in depth):

| Network              | Exposed? | Members                                                    |
|----------------------|----------|------------------------------------------------------------|
| `public-network`     | yes      | nginx, grafana, alertmanager, cadvisor                     |
| `private-network`    | internal | nginx, frontend, backend                                   |
| `db-network`         | internal | backend, db                                                |
| `monitoring-network` | internal | nginx, backend + all observability services                |

Only `db` reaches the database network; only the observability stack reaches
`monitoring-network`; the database is never on a host-published port.

## Services

The stack is composed of an **application tier**, a **data tier**, and an
**observability tier**, all orchestrated by `docker-compose.yml`.

### Application & data

| Service    | Image / Build     | Port (host:container) | Purpose                                   |
|------------|-------------------|-----------------------|-------------------------------------------|
| `nginx`    | `nginx:1.27.2`    | `80:80`               | Edge reverse proxy / router (single entry)|
| `frontend` | build `./frontend`| internal `80`         | Static UI (Nginx + vanilla JS/CSS/HTML)   |
| `backend`  | build `./backend` | internal `8000`       | FastAPI + SQLAlchemy REST API             |
| `db`       | `mysql:8.0`       | internal `3306`       | MySQL 8 database (persistent volume)      |

### Observability

| Service         | Image                          | Port (host:container) | Purpose                                 |
|-----------------|--------------------------------|-----------------------|-----------------------------------------|
| `prometheus`    | `prom/prometheus:v2.54.1`      | `9090:9090`           | Metrics scraping, storage & alert rules |
| `grafana`       | `grafana/grafana:11.2.0`       | `3100:3000`           | Dashboards (metrics + logs)             |
| `loki`          | `grafana/loki:3.2.0`           | internal `3100`       | Log aggregation store                   |
| `promtail`      | `grafana/promtail:3.2.0`       | internal `9080`       | Ships container logs → Loki             |
| `alertmanager`  | `prom/alertmanager:v0.27.0`    | internal `9093`       | Routes alerts (Telegram)                |
| `cadvisor`      | `cadvisor:v0.49.1`             | `8082:8080`           | Per-container resource metrics          |
| `node-exporter` | `prom/node-exporter:v1.8.2`    | internal `9100`       | Host-level metrics (CPU/mem/disk)       |

**Operational conventions** applied to every service: `restart: unless-stopped`,
`mem_limit` / `cpus` caps, and `healthcheck` probes. Application logs use the
Docker `json-file`/`local` drivers with size-based rotation.

## Project Structure

Grouped by concern so the DevOps surface (orchestration, monitoring, CI/CD,
secrets, ops scripts) is separated from application code.

```
.
├── docker-compose.yml          # Orchestration: all 12 services, networks, volumes, secrets
├── install.sh                  # Bootstrap: install Docker, clone, seed env/secrets, up -d
├── .env.example                # Non-secret config template  →  copy to .env
│
├── backend/                    # ── Application: API ──────────────────────────
│   ├── app/                    #   FastAPI app (main, routes, crud, models, schemas,
│   │                           #   config, database, health)
│   ├── alembic/                #   DB migrations
│   ├── tests/                  #   pytest suite (run in CI)
│   ├── Dockerfile              #   Backend image (Hadolint-linted, Trivy-scanned in CI)
│   ├── requirements.txt
│   └── init.sql                #   Schema + seed, auto-loaded by MySQL on first boot
│
├── frontend/                   # ── Application: UI ───────────────────────────
│   ├── index.html · style.css · app.js
│   ├── nginx.conf              #   Static-serving config (inside the frontend image)
│   └── Dockerfile
│
├── nginx/                      # ── Edge reverse proxy ────────────────────────
│   └── nginx.conf              #   Routes /api, /grafana, /prometheus, /alertmanager, /
│
├── prometheus/                 # ── Observability: metrics ────────────────────
│   ├── prometheus.yml          #   Scrape targets + Alertmanager wiring
│   └── alerts.yml              #   Alerting rules
├── alertmanager/
│   └── alertmanager.yml        #   Alert routing (Telegram receiver)
├── promtail/
│   └── promtail-config.yml     #   Log-shipping config (Docker logs → Loki)
├── grafana/                    # ── Observability: dashboards ─────────────────
│   ├── provisioning/           #   Auto-provisioned datasources + dashboard loader
│   ├── dashboards/             #   Dashboard JSON (RED, node, cAdvisor, Prometheus)
│   └── scripts/                #   fetch_dashboards.sh helper
│
├── scripts/                    # ── Operations ────────────────────────────────
│   ├── backup.sh               #   Consistent mysqldump → ./backups, with retention
│   ├── restore.sh              #   Restore from a dump
│   └── verify-restore.sh       #   Sanity-check a restore
│
├── secrets/                    # ── Secrets (Docker secrets; *.example tracked) ─
│   └── *.example               #   db_password, mysql_root_password,
│                               #   grafana_admin_password, telegram_token
│
├── .github/workflows/ci.yml    # ── CI/CD: lint+test → build+Trivy scan → push ─
├
└── README.md
```

## Features

### Backend
- RESTful CRUD APIs for task management
- Health check endpoint
- SQLAlchemy ORM with SQLAlchemy 2.x
- Pydantic validation
- Request/error logging
- MySQL 8 integration
- Alembic migrations
- FastAPI Swagger documentation

### Frontend
- Task listing with real-time updates
- Create, edit, and delete tasks
- Status management (pending/completed)
- Responsive design
- Configurable backend URL
- No external framework dependencies

## Environment Configuration

Non-secret settings live in the root `.env` file (copy it from the template):
```bash
cp .env.example .env
```
```env
DB_HOST=db
DB_PORT=3306
DB_DATABASE=appdb
DB_USERNAME=appuser
```

Passwords and tokens are **not** stored here — they are Docker secrets under
`./secrets/*` (git-ignored). See [ROADMAP.md](./ROADMAP.md) for setup details.

## Documentation

- [Backend README](./backend/README.md)
- [Frontend README](./frontend/README.md)

## API Reference

### List Tasks
```http
GET /api/tasks
```

### Get Task
```http
GET /api/tasks/{id}
```

### Create Task
```http
POST /api/tasks
Content-Type: application/json

{
  "name": "Task name",
  "description": "Optional description",
  "status": "pending"
}
```

### Update Task
```http
PUT /api/tasks/{id}
Content-Type: application/json

{
  "name": "Updated name",
  "status": "completed"
}
```

### Delete Task
```http
DELETE /api/tasks/{id}
```

### Health Check
```http
GET /health
```

## Development

### Run Backend Locally
```bash
cd backend
pip install -r requirements.txt
python -m uvicorn app.main:app --reload
```

### Run Frontend Locally
Open `frontend/index.html` in a browser or use:
```bash
cd frontend
python -m http.server 8080
# Then visit http://localhost:8080
```

## Notes

- Database initialization is automatic via `init.sql`
- Sample tasks are pre-inserted
- Frontend auto-detects backend host in Docker
- All containers restart automatically on failure
- Production-ready code with proper error handling and logging
