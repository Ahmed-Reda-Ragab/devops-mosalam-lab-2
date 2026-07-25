from sqlalchemy.orm import Session

from . import models, schemas


def get_tasks(db: Session) -> list[models.Task]:
    return db.query(models.Task).order_by(models.Task.id).all()


def get_tasks_paginated(db: Session, page: int = 1, limit: int = 10) -> tuple[list[models.Task], int]:
    """Get paginated tasks with total count.
    
    Args:
        db: Database session
        page: Page number (1-indexed)
        limit: Items per page
    
    Returns:
        Tuple of (tasks list, total count)
    """
    # Ensure valid page and limit
    page = max(1, page)
    limit = max(1, min(limit, 100))  # Cap at 100 items per page
    
    query = db.query(models.Task).order_by(models.Task.id)
    total = query.count()
    
    # Calculate offset and fetch
    offset = (page - 1) * limit
    tasks = query.offset(offset).limit(limit).all()
    
    return tasks, total


def get_task(db: Session, task_id: int) -> models.Task | None:
    return db.query(models.Task).filter(models.Task.id == task_id).first()


def create_task(db: Session, task: schemas.TaskCreate) -> models.Task:
    db_task = models.Task(
        name=task.name,
        description=task.description,
        status=task.status.value if task.status else None,
    )
    db.add(db_task)
    # Flush to send the INSERT and populate the primary key
    db.flush()
    # Refresh before commit to load server-side defaults (timestamps, enums)
    db.refresh(db_task)
    # Commit the transaction
    db.commit()
    return db_task


def update_task(db: Session, db_task: models.Task, task_update: schemas.TaskUpdate) -> models.Task:
    if task_update.name is not None:
        db_task.name = task_update.name
    if task_update.description is not None:
        db_task.description = task_update.description
    if task_update.status is not None:
        db_task.status = task_update.status.value
    db.flush()
    db.refresh(db_task)
    db.commit()
    return db_task


def delete_task(db: Session, db_task: models.Task) -> None:
    db.delete(db_task)
    db.commit()

