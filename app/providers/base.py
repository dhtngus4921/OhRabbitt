from typing import Protocol

from app.models import Product


class ProductProvider(Protocol):
    async def list_products(self) -> list[Product]:
        """Return Gmarket products with coupon information."""
