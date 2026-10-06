"""Source 1: daily orders CSV file drop.

    python -m datagen.orders --date 2026-01-05 --rows 300 --env dev --upload

Each file contains ~3% orders for customers that do not exist and ~2% exact
duplicate rows, so the pipeline has real data-quality problems to handle.
"""

import argparse
import csv
import datetime as dt
import random
from pathlib import Path

from datagen.common import N_CUSTOMERS, customer_id, iso_utc, raw_bucket_name, upload_file

ORDER_COLUMNS = [
    "order_id",
    "customer_id",
    "order_ts",
    "product_sku",
    "quantity",
    "unit_price",
    "status",
]

PRODUCTS = {
    "P100": 19.99,
    "P200": 49.50,
    "P300": 5.25,
    "P400": 129.00,
    "P500": 9.99,
    "P600": 74.90,
}
STATUSES = ["placed", "shipped", "delivered", "cancelled"]


def generate_orders(day, rows=300):
    rng = random.Random(f"orders-{day.isoformat()}")
    skus = list(PRODUCTS)
    orders = []
    for i in range(1, rows + 1):
        if rng.random() < 0.03:
            cust = f"C9{rng.randint(0, 999):03d}"  # unknown customer, on purpose
        else:
            cust = customer_id(rng.randint(1, N_CUSTOMERS))
        ordered_at = dt.datetime.combine(day, dt.time()) + dt.timedelta(
            seconds=rng.randint(0, 86399)
        )
        sku = rng.choice(skus)
        orders.append(
            {
                "order_id": f"O{day:%Y%m%d}{i:05d}",
                "customer_id": cust,
                "order_ts": iso_utc(ordered_at),
                "product_sku": sku,
                "quantity": rng.randint(1, 5),
                "unit_price": f"{PRODUCTS[sku]:.2f}",
                "status": rng.choice(STATUSES),
            }
        )
    duplicates = [dict(row) for row in rng.sample(orders, k=max(1, rows // 50))]
    return orders + duplicates


def write_csv(path, rows):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=ORDER_COLUMNS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    return path


def main(argv=None):
    parser = argparse.ArgumentParser(description="Generate a daily orders CSV file")
    parser.add_argument("--date", default=dt.date.today().isoformat(), help="YYYY-MM-DD")
    parser.add_argument("--rows", type=int, default=300)
    parser.add_argument("--env", default="dev", choices=["dev", "prod"])
    parser.add_argument("--out-dir", default="out")
    parser.add_argument("--upload", action="store_true", help="Upload to the raw bucket")
    args = parser.parse_args(argv)

    day = dt.date.fromisoformat(args.date)
    rows = generate_orders(day, args.rows)
    filename = f"orders_{day.isoformat()}.csv"
    path = write_csv(Path(args.out_dir) / filename, rows)
    print(f"Wrote {len(rows)} rows to {path}")

    if args.upload:
        upload_file(path, raw_bucket_name(args.env), f"orders/{filename}")


if __name__ == "__main__":
    main()
