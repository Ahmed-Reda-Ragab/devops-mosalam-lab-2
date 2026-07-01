from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    db_host: str
    db_port: int = 3306
    db_database: str
    db_username: str
    db_password: str

    @property
    def database_url(self) -> str:
        return (
            f"mysql+pymysql://{self.db_username}:{self.db_password}@{self.db_host}:{self.db_port}/{self.db_database}?charset=utf8mb4"
        )

    model_config = SettingsConfigDict(case_sensitive=False)


settings = Settings()
