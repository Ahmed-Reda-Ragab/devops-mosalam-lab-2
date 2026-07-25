from locust import HttpUser, between, task
import random


class TaskUser(HttpUser):
    wait_time = between(1, 2)
    task_ids = []  # Store created task IDs for deletion

    def on_start(self):
        """Called when a user starts"""
        self.task_ids = []

    @task(3)
    def list_tasks(self):
        self.client.get("/api/tasks", name="GET /api/tasks")

    @task(1)
    def health_check(self):
        self.client.get("/health", name="GET /health")

    @task(2)
    def create_task(self):
        payload = {
            "name": "Load test task",
            "description": "created by locust",
            "status": "pending",
        }
        response = self.client.post("/api/tasks", json=payload, name="POST /api/tasks")
        # Store task ID for later deletion
        if response.status_code == 201:
            try:
                task_id = response.json().get("id")
                if task_id:
                    self.task_ids.append(task_id)
            except:
                pass

    @task(1)
    def delete_task(self):
        # Only delete if we have created tasks
        if not self.task_ids:
            return
        
        # Pick a random task ID to delete
        task_id = random.choice(self.task_ids)
        self.client.delete(f"/api/tasks/{task_id}", name="DELETE /api/tasks")
        # Remove from list
        self.task_ids.remove(task_id)
