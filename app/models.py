from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, Field, HttpUrl, field_validator


class Product(BaseModel):
    id: str
    name: str
    url: HttpUrl | None = None
    price: Decimal = Field(gt=0)
    coupon_discount_amount: Decimal | None = Field(default=None, ge=0)
    coupon_discount_rate: Decimal | None = Field(default=None, ge=0, le=100)
    category: str | None = None
    seller: str | None = None
    metadata: dict[str, str | int | float | bool | None] = Field(default_factory=dict)

    @field_validator("coupon_discount_rate")
    @classmethod
    def normalize_percent(cls, value: Decimal | None) -> Decimal | None:
        if value is None:
            return None
        if value <= 1:
            return value * Decimal("100")
        return value


class RankedProduct(BaseModel):
    rank: int
    product: Product
    coupon_apply_rate: Decimal
    effective_price: Decimal


class WeeklyRecommendation(BaseModel):
    week_key: str
    generated_at: datetime
    category: str | None
    products: list[RankedProduct]
