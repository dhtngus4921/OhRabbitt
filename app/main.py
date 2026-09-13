from typing import Annotated

from fastapi import Depends, FastAPI, Query

from app.config import Settings, get_settings
from app.providers.base import ProductProvider
from app.providers.csv_provider import CsvProductProvider
from app.providers.http_provider import HttpProductProvider
from app.services.recommendation_service import RecommendationService


app = FastAPI(title="Gmarket Weekly Coupon API", version="0.1.0")


def get_provider(settings: Annotated[Settings, Depends(get_settings)]) -> ProductProvider:
    if settings.gmarket_products_url:
        return HttpProductProvider(
            url=settings.gmarket_products_url,
            auth_header=settings.gmarket_products_auth_header,
            timeout_seconds=settings.request_timeout_seconds,
        )
    return CsvProductProvider(settings.csv_products_path)


def get_recommendation_service(
    provider: Annotated[ProductProvider, Depends(get_provider)],
) -> RecommendationService:
    return RecommendationService(provider)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/v1/recommendations/gmarket/weekly")
async def get_weekly_gmarket_recommendations(
    service: Annotated[RecommendationService, Depends(get_recommendation_service)],
    category: Annotated[str | None, Query(description="Optional category filter")] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 10,
    force_refresh: bool = False,
):
    return await service.get_weekly_recommendations(
        category=category,
        limit=limit,
        force_refresh=force_refresh,
    )


@app.post("/api/v1/recommendations/gmarket/weekly/refresh")
async def refresh_weekly_gmarket_recommendations(
    service: Annotated[RecommendationService, Depends(get_recommendation_service)],
    category: Annotated[str | None, Query(description="Optional category filter")] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 10,
):
    return await service.get_weekly_recommendations(
        category=category,
        limit=limit,
        force_refresh=True,
    )
