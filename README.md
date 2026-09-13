# Gmarket Weekly Coupon API

FastAPI service that selects the Gmarket products with the highest coupon discount rate each week.

## Git sync workflow

Run this before starting work. It only pulls when the working tree is clean, and uses fast-forward mode to avoid creating an unintended merge commit.

```powershell
.\git-start.ps1
```

Run this after finishing work. It stages all non-ignored changes, commits them, and pushes the current branch.

```powershell
.\git-finish.ps1 "Describe the completed work"
```

If the commit message is omitted, the script uses the current date and time.

## Endpoints

- `GET /api/v1/recommendations/gmarket/weekly`
  - Returns the current week's recommended products.
  - Caches the result within the same ISO week.
  - Use `force_refresh=true` to recalculate immediately.
- `POST /api/v1/recommendations/gmarket/weekly/refresh`
  - Forces a refresh for the current week.
- `GET /health`
  - Health check.

## Run

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn app.main:app --reload
```

I could not run this locally in the current workspace because the Python runtime is not installed; only the Microsoft Store Python launcher is available.

## Data Source

The default provider reads `data/sample_gmarket_products.csv`.

To connect a real Gmarket, ESM, affiliate, or internal product feed, expose it as a JSON endpoint and set:

```powershell
$env:GMARKET_PRODUCTS_URL="https://example.com/products.json"
$env:GMARKET_PRODUCTS_AUTH_HEADER="Bearer <token>"
uvicorn app.main:app --reload
```

Supported JSON formats:

```json
[
  {
    "id": "123",
    "name": "Product name",
    "url": "https://item.gmarket.co.kr/Item?goodscode=123",
    "price": 10000,
    "coupon_discount_amount": 1500,
    "category": "digital",
    "seller": "seller"
  }
]
```

```json
{
  "products": [
    {
      "id": "123",
      "name": "Product name",
      "url": "https://item.gmarket.co.kr/Item?goodscode=123",
      "price": 10000,
      "coupon_discount_rate": 15
    }
  ]
}
```

Coupon rate calculation:

- If `coupon_discount_rate` exists, it is used first.
- If it does not exist, the service calculates `coupon_discount_amount / price * 100`.
- Fraction rates like `0.18` are normalized to `18.00`.
