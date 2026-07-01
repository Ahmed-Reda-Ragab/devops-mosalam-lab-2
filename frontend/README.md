# Frontend Task Manager

A simple HTML/CSS/JavaScript web application for managing tasks via the Task Manager API.

## Features
- List tasks
- Create new tasks
- Update task status and details
- Delete tasks
- Responsive design

## Backend Configuration
By default, the frontend connects to `http://localhost:8000`.

When running via Docker Compose, the frontend automatically detects the host and connects to `http://{hostname}:8000`.

To specify a different backend URL, add it as a query parameter:
```
http://localhost/?backend=example.com:8000
```

## Docker
Build and run with Docker Compose:
```bash
docker compose up --build
```

The frontend will be available at `http://localhost`.

## Development
Open `index.html` directly in a browser:
```bash
# Windows
start index.html

# macOS
open index.html

# Linux
xdg-open index.html
```
