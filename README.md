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
- **Frontend**: http://localhost
- **API**: http://localhost:8000
- **API Docs**: http://localhost:8000/docs
- **Database**: localhost:3306

## Architecture

```
frontend/        → Nginx + vanilla JS/CSS/HTML
backend/         → FastAPI + SQLAlchemy
docker-compose   → Orchestrates all services + MySQL
```

## Services

| Service  | Port | Technology      |
|----------|------|-----------------|
| Frontend | 80   | Nginx           |
| Backend  | 8000 | FastAPI/Uvicorn |
| Database | 3306 | MySQL 8.0       |

## Project Structure

```
.
├── backend/
│   ├── app/
│   │   ├── main.py
│   │   ├── database.py
│   │   ├── models.py
│   │   ├── schemas.py
│   │   ├── crud.py
│   │   ├── routes.py
│   │   ├── config.py
│   │   └── health.py
│   ├── alembic/
│   ├── requirements.txt
│   ├── Dockerfile
│   ├── .env
│   ├── init.sql
│   └── README.md
│
├── frontend/
│   ├── index.html
│   ├── style.css
│   ├── app.js
│   ├── nginx.conf
│   ├── Dockerfile
│   └── README.md
│
└── docker-compose.yml
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

Edit `backend/.env`:
```env
DB_HOST=db
DB_PORT=3306
DB_DATABASE=appdb
DB_USERNAME=appuser
DB_PASSWORD=secret
```

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
