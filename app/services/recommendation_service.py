from datetime import UTC, datetime

from app.models import WeeklyRecommendation
from app.providers.base import ProductProvider
from app.services.ranking import rank_products


class RecommendationService:
    _cache: dict[tuple[str, str | None, int], WeeklyRecommendation] = {}

    def __init__(self, provider: ProductProvider) -> None:
        self.provider = provider

    async def get_weekly_recommendations(
        self,
        *,
        category: str | None,
        limit: int,
        force_refresh: bool = False,
    ) -> WeeklyRecommendation:
        now = datetime.now(UTC)
        week_key = self._week_key(now)
        cache_key = (week_key, category, limit)

        if not force_refresh and cache_key in self._cache:
            return self._cache[cache_key]

        products = await self.provider.list_products()
        recommendation = WeeklyRecommendation(
            week_key=week_key,
            generated_at=now,
            category=category,
            products=rank_products(products, limit=limit, category=category),
        )
        self._cache[cache_key] = recommendation
        return recommendation

    @staticmethod
    def _week_key(value: datetime) -> str:
        iso_year, iso_week, _ = value.isocalendar()
        return f"{iso_year}-W{iso_week:02d}"
