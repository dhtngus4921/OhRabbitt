from decimal import Decimal, ROUND_HALF_UP

from app.models import Product, RankedProduct


RATE_QUANT = Decimal("0.01")
MONEY_QUANT = Decimal("1")


def coupon_apply_rate(product: Product) -> Decimal:
    if product.coupon_discount_rate is not None:
        return product.coupon_discount_rate.quantize(RATE_QUANT, rounding=ROUND_HALF_UP)

    if product.coupon_discount_amount is None:
        return Decimal("0.00")

    rate = product.coupon_discount_amount / product.price * Decimal("100")
    return rate.quantize(RATE_QUANT, rounding=ROUND_HALF_UP)


def effective_price(product: Product) -> Decimal:
    if product.coupon_discount_amount is not None:
        price = max(product.price - product.coupon_discount_amount, Decimal("0"))
    elif product.coupon_discount_rate is not None:
        price = product.price * (Decimal("100") - product.coupon_discount_rate) / Decimal("100")
        price = max(price, Decimal("0"))
    else:
        price = product.price
    return price.quantize(MONEY_QUANT, rounding=ROUND_HALF_UP)


def rank_products(products: list[Product], *, limit: int, category: str | None = None) -> list[RankedProduct]:
    filtered = [
        product
        for product in products
        if category is None or (product.category or "").casefold() == category.casefold()
    ]
    ordered = sorted(
        filtered,
        key=lambda product: (
            coupon_apply_rate(product),
            product.coupon_discount_amount or Decimal("0"),
            product.price,
        ),
        reverse=True,
    )

    return [
        RankedProduct(
            rank=index + 1,
            product=product,
            coupon_apply_rate=coupon_apply_rate(product),
            effective_price=effective_price(product),
        )
        for index, product in enumerate(ordered[:limit])
    ]
