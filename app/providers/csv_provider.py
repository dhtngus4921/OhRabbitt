import csv
from pathlib import Path

from app.models import Product


class CsvProductProvider:
    def __init__(self, path: Path) -> None:
        self.path = path

    async def list_products(self) -> list[Product]:
        if not self.path.exists():
            raise FileNotFoundError(f"Product CSV not found: {self.path}")

        with self.path.open("r", encoding="utf-8-sig", newline="") as file:
            reader = csv.DictReader(file)
            return [self._parse_row(row) for row in reader]

    def _parse_row(self, row: dict[str, str]) -> Product:
        return Product(
            id=row["id"],
            name=row["name"],
            url=row.get("url") or None,
            price=row["price"],
            coupon_discount_amount=row.get("coupon_discount_amount") or None,
            coupon_discount_rate=row.get("coupon_discount_rate") or None,
            category=row.get("category") or None,
            seller=row.get("seller") or None,
        )
