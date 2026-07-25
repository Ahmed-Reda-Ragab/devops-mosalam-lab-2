from locust import HttpUser, between, task


class TaskUser(HttpUser):
    wait_time = between(1, 2)

    @task(3)
    def list_tasks(self):
        self.client.get("/api/tasks", name="GET /api/tasks")

    @task(1)
    def health_check(self):
        self.client.get("/health", name="GET /health")

    @task(1)
    def create_task(self):
        payload = {
            "name": "Load test task",
            "description": "created by locust web",
            "status": "pending",
        }
        self.client.post("/api/tasks", json=payload, name="POST /api/tasks")
