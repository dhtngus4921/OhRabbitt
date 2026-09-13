from functools import lru_cache
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    app_name: str = "Gmarket Weekly Coupon API"
    csv_products_path: Path = Field(
        default=Path("data/sample_gmarket_products.csv"),
        validation_alias="GMARKET_PRODUCTS_CSV",
    )
    gmarket_products_url: str | None = Field(
        default=None,
        validation_alias="GMARKET_PRODUCTS_URL",
    )
    gmarket_products_auth_header: str | None = Field(
        default=None,
        validation_alias="GMARKET_PRODUCTS_AUTH_HEADER",
    )
    request_timeout_seconds: float = 10.0


@lru_cache
def get_settings() -> Settings:
    return Settings()
