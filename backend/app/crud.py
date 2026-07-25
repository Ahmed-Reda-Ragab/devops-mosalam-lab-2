from sqlalchemy.orm import Session

from . import models, schemas


def get_tasks(db: Session) -> list[models.Task]:
    return db.query(models.Task).order_by(models.Task.id).all()


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
    # Commit the transaction
    db.commit()
    # Refresh to load any server-side defaults (timestamps, enums) after commit
    db.refresh(db_task)
    return db_task


def update_task(db: Session, db_task: models.Task, task_update: schemas.TaskUpdate) -> models.Task:
    if task_update.name is not None:
        db_task.name = task_update.name
    if task_update.description is not None:
        db_task.description = task_update.description
    if task_update.status is not None:
        db_task.status = task_update.status.value
    db.commit()
    db.refresh(db_task)
    return db_task


def delete_task(db: Session, db_task: models.Task) -> None:
    db.delete(db_task)
    db.commit()
    db.refresh(db_task)

