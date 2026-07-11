from app.main import app
from fastapi.testclient import TestClient

client = TestClient(app)


def test_openapi_available():
    resp = client.get("/openapi.json")
    assert resp.status_code == 200
    assert resp.json()["info"]["title"] == "Task Manager API"


def test_expected_routes_registered():
    paths = client.get("/openapi.json").json()["paths"]
    assert "/health" in paths
    assert "/api/tasks" in paths
    assert "/api/tasks/{task_id}" in paths


def test_metrics_endpoint_exposed():
    resp = client.get("/metrics")
    assert resp.status_code == 200
    assert "python_info" in resp.text


def test_unknown_route_returns_404():
    assert client.get("/definitely-not-a-route").status_code == 404
