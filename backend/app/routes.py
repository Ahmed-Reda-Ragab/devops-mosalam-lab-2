from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from . import crud, database, schemas
from .cache import cache_service
import socket

router = APIRouter(prefix="/api")
container_id = socket.gethostname()

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
def list_tasks(page: int = 1, limit: int = 10, db: Session = Depends(database.get_db)):
    # Cache key includes pagination parameters
    cache_key = f"tasks:page:{page}:limit:{limit}"
    cached = cache_service.get(cache_key)
    if cached is not None:
        pagination = cached.get("pagination", {})
        return schemas.TaskListResponse(
            tasks=[schemas.TaskRead.model_validate(item) for item in cached.get("tasks", [])],
            pagination=schemas.PaginationMeta(**pagination),
            source="cache",
            message="Tasks loaded from cache",
            container=container_id,
        )

    tasks, total = crud.get_tasks_paginated(db, page, limit)
    serialized = [_serialize_task(task) for task in tasks]
    
    # Calculate pagination metadata
    pages = (total + limit - 1) // limit  # Ceiling division
    pagination_meta = schemas.PaginationMeta(
        page=page,
        limit=limit,
        total=total,
        pages=pages,
    )
    
    cache_data = {
        "tasks": serialized,
        "pagination": pagination_meta.model_dump(),
    }
    cache_service.set(cache_key, cache_data, ttl=60)
    
    return schemas.TaskListResponse(
        tasks=[schemas.TaskRead.model_validate(item) for item in serialized],
        pagination=pagination_meta,
        source="db",
        message="Tasks loaded from database",
        container=container_id,
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
    # Clear all pagination caches
    cache_service.delete_prefix("tasks:page:")
    return task


@router.put("/tasks/{task_id}", response_model=schemas.TaskRead, status_code=status.HTTP_200_OK)
def update_task(task_id: int, task_in: schemas.TaskUpdate, db: Session = Depends(database.get_db)):
    task = crud.get_task(db, task_id)
    if task is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")
    updated_task = crud.update_task(db, task, task_in)
    # Clear all pagination caches
    cache_service.delete_prefix("tasks:page:")
    return updated_task


@router.delete("/tasks/{task_id}", status_code=status.HTTP_200_OK)
def delete_task(task_id: int, db: Session = Depends(database.get_db)):
    task = crud.get_task(db, task_id)
    if task is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")
    crud.delete_task(db, task)
    # Clear all pagination caches
    cache_service.delete_prefix("tasks:page:")
    return {"detail": "Task deleted"}
