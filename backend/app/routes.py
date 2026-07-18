from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from . import crud, database, schemas
from .cache import cache_service

router = APIRouter(prefix="/api")


def _serialize_task(task) -> dict:
    status_value = task.status.value if getattr(task, "status", None) is not None and hasattr(task.status, "value") else task.status
    return {
        "id": task.id,
        "name": task.name,
        "description": task.description,
        "status": status_value,
        "created_at": task.created_at,
        "updated_at": task.updated_at,
    }


@router.get("/tasks", response_model=schemas.TaskListResponse, status_code=status.HTTP_200_OK)
def list_tasks(db: Session = Depends(database.get_db)):
    cache_key = "tasks:all"
    cached = cache_service.get(cache_key)
    if cached is not None:
        return schemas.TaskListResponse(
            tasks=[schemas.TaskRead.model_validate(item) for item in cached],
            source="cache",
            message="Tasks loaded from cache",
        )

    tasks = crud.get_tasks(db)
    serialized = [_serialize_task(task) for task in tasks]
    cache_service.set(cache_key, serialized, ttl=60)
    return schemas.TaskListResponse(
        tasks=[schemas.TaskRead.model_validate(item) for item in serialized],
        source="db",
        message="Tasks loaded from database",
    )


@router.get("/tasks/{task_id}", response_model=schemas.TaskRead, status_code=status.HTTP_200_OK)
def get_task(task_id: int, db: Session = Depends(database.get_db)):
    task = crud.get_task(db, task_id)
    if task is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")
    return task


@router.post("/tasks", response_model=schemas.TaskRead, status_code=status.HTTP_201_CREATED)
def create_task(task_in: schemas.TaskCreate, db: Session = Depends(database.get_db)):
    task = crud.create_task(db, task_in)
    cache_service.delete("tasks:all")
    return task


@router.put("/tasks/{task_id}", response_model=schemas.TaskRead, status_code=status.HTTP_200_OK)
def update_task(task_id: int, task_in: schemas.TaskUpdate, db: Session = Depends(database.get_db)):
    task = crud.get_task(db, task_id)
    if task is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")
    updated_task = crud.update_task(db, task, task_in)
    cache_service.delete("tasks:all")
    return updated_task


@router.delete("/tasks/{task_id}", status_code=status.HTTP_200_OK)
def delete_task(task_id: int, db: Session = Depends(database.get_db)):
    task = crud.get_task(db, task_id)
    if task is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")
    crud.delete_task(db, task)
    cache_service.delete("tasks:all")
    return {"detail": "Task deleted"}
