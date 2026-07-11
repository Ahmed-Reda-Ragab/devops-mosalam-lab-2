from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from . import crud, database, schemas

router = APIRouter(prefix="/api")


@router.get("/tasks", response_model=list[schemas.TaskRead], status_code=status.HTTP_200_OK)
def list_tasks(db: Session = Depends(database.get_db)):
    return crud.get_tasks(db)


@router.get("/tasks/{task_id}", response_model=schemas.TaskRead, status_code=status.HTTP_200_OK)
def get_task(task_id: int, db: Session = Depends(database.get_db)):
    task = crud.get_task(db, task_id)
    if task is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")
    return task


@router.post("/tasks", response_model=schemas.TaskRead, status_code=status.HTTP_201_CREATED)
def create_task(task_in: schemas.TaskCreate, db: Session = Depends(database.get_db)):
    return crud.create_task(db, task_in)


@router.put("/tasks/{task_id}", response_model=schemas.TaskRead, status_code=status.HTTP_200_OK)
def update_task(task_id: int, task_in: schemas.TaskUpdate, db: Session = Depends(database.get_db)):
    task = crud.get_task(db, task_id)
    if task is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")
    return crud.update_task(db, task, task_in)


@router.delete("/tasks/{task_id}", status_code=status.HTTP_200_OK)
def delete_task(task_id: int, db: Session = Depends(database.get_db)):
    task = crud.get_task(db, task_id)
    if task is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")
    crud.delete_task(db, task)
    return {"detail": "Task deleted"}
