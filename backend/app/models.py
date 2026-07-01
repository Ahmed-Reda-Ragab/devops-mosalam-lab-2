from sqlalchemy import BigInteger, Column, String, Text, TIMESTAMP, func
from sqlalchemy.dialects.mysql import ENUM as MySQLEnum
from sqlalchemy.orm import declarative_base

Base = declarative_base()

status_enum = MySQLEnum("pending", "completed", name="task_status", values_callable=lambda obj: obj)


class Task(Base):
    __tablename__ = "tasks"

    id = Column(BigInteger, primary_key=True, autoincrement=True)
    name = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)
    status = Column(status_enum, nullable=False, server_default="pending")
    created_at = Column(TIMESTAMP, nullable=False, server_default=func.current_timestamp())
    updated_at = Column(
        TIMESTAMP,
        nullable=False,
        server_default=func.current_timestamp(),
        onupdate=func.current_timestamp(),
    )
