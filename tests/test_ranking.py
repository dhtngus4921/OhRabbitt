from decimal import Decimal

from app.models import Product
from app.services.ranking import coupon_apply_rate, effective_price, rank_products


def test_coupon_apply_rate_from_amount() -> None:
    product = Product(id="1", name="sample", price=Decimal("10000"), coupon_discount_amount=Decimal("2500"))

    assert coupon_apply_rate(product) == Decimal("25.00")
    assert effective_price(product) == Decimal("7500")


def test_coupon_apply_rate_normalizes_fraction_rate() -> None:
    product = Product(id="1", name="sample", price=Decimal("10000"), coupon_discount_rate=Decimal("0.15"))

    assert coupon_apply_rate(product) == Decimal("15.00")
    assert effective_price(product) == Decimal("8500")


def test_rank_products_orders_by_highest_coupon_rate() -> None:
    products = [
        Product(id="low", name="low", price=Decimal("10000"), coupon_discount_amount=Decimal("1000")),
        Product(id="high", name="high", price=Decimal("10000"), coupon_discount_amount=Decimal("3000")),
    ]

    ranked = rank_products(products, limit=1)

    assert ranked[0].product.id == "high"
    assert ranked[0].coupon_apply_rate == Decimal("30.00")
