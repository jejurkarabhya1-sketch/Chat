from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import model_validator

class Settings(BaseSettings):
    app_env: str = "development"
    database_url: str = "sqlite:///./relay.db"
    jwt_secret: str = "unsafe-development-secret-change-this"
    access_token_minutes: int = 30
    cors_origins: str = "http://localhost:3000"
    firebase_project_id: str = ""
    redis_url: str = ""
    allow_plaintext_messages: bool = False
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @model_validator(mode="after")
    def validate_production_settings(self):
        if self.app_env.lower() == "production":
            if len(self.jwt_secret) < 32 or self.jwt_secret == "unsafe-development-secret-change-this":
                raise ValueError("Production requires a unique JWT_SECRET of at least 32 characters")
            if not self.firebase_project_id.strip():
                raise ValueError("Production requires FIREBASE_PROJECT_ID")
            if self.database_url.startswith("sqlite"):
                raise ValueError("Production must use PostgreSQL or another supported production database")
            if self.allow_plaintext_messages:
                raise ValueError("Production must disable plaintext messages until audited E2EE is implemented")
            raise ValueError("Production startup is blocked: the client-side end-to-end encryption protocol is not implemented and independently audited")
        return self

# Instantiate once at process startup so API modules and migration tooling share
# the validated environment configuration.
settings = Settings()
