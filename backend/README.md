# Backend Task API

## Requirements
- Python 3.12
- Docker
- Docker Compose

## Setup
1. Copy environment file:
   ```bash
   cp backend/.env.example backend/.env
   ```
2. Start services:
   ```bash
   docker compose up --build
   ```

## Services
- **API**: http://localhost:8000
- **Frontend**: http://localhost
- **Database**: localhost:3306

## API endpoints
- `GET /api/tasks` — List all tasks
- `GET /api/tasks/{id}` — Get a specific task
- `POST /api/tasks` — Create a new task
- `PUT /api/tasks/{id}` — Update a task
- `DELETE /api/tasks/{id}` — Delete a task
- `GET /health` — Health check

## Swagger
- API Docs: `http://localhost:8000/docs`
- OpenAPI spec: `http://localhost:8000/openapi.json`

## Database migrations
Run migrations after the database is available:
```bash
cd backend
alembic upgrade head
```

## Notes
- `init.sql` seeds the database with sample tasks during MySQL initialization.
- The frontend is containerized and available in the `frontend/` folder.
- Both frontend and backend are managed via Docker Compose.
