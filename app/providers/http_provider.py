import httpx

from app.models import Product


class HttpProductProvider:
    def __init__(
        self,
        url: str,
        auth_header: str | None,
        timeout_seconds: float,
    ) -> None:
        self.url = url
        self.auth_header = auth_header
        self.timeout_seconds = timeout_seconds

    async def list_products(self) -> list[Product]:
        headers = {}
        if self.auth_header:
            headers["Authorization"] = self.auth_header

        async with httpx.AsyncClient(timeout=self.timeout_seconds) as client:
            response = await client.get(self.url, headers=headers)
            response.raise_for_status()

        payload = response.json()
        rows = payload.get("products", payload) if isinstance(payload, dict) else payload
        if not isinstance(rows, list):
            raise ValueError("Product response must be a JSON array or an object with a products array.")

        return [Product.model_validate(row) for row in rows]
