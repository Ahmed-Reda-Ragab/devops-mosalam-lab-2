# Locust load testing

This folder contains a Locust test plan for the local app.

## Run on Windows

From PowerShell:

```powershell
Set-Location .\locust
.\run_locust.ps1
```

Then open:

```text
http://localhost:8089
```

## Notes
- The test targets the local app via `http://localhost`.
- If you want to test through Traefik instead, change the host to `http://localhost` and ensure the app is reachable there.
- The test script uses the API endpoints `/api/tasks`, `/health`, and `/api/tasks` for POST.
