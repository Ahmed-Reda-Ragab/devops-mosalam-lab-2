from pydantic import BaseSettings, Field


class Settings(BaseSettings):
    db_host: str = Field(..., env="DB_HOST")
    db_port: int = Field(3306, env="DB_PORT")
    db_database: str = Field(..., env="DB_DATABASE")
    db_username: str = Field(..., env="DB_USERNAME")
    db_password: str = Field(..., env="DB_PASSWORD")

    @property
    def database_url(self) -> str:
        return (
            f"mysql+pymysql://{self.db_username}:{self.db_password}@{self.db_host}:{self.db_port}/{self.db_database}?charset=utf8mb4"
        )

    class Config:
        case_sensitive = True


settings = Settings()
