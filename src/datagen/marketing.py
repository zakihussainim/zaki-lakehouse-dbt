"""Source 3: periodic marketing-list file drops (full snapshot each time).

    python -m datagen.marketing --drop 1 --env dev --upload
    python -m datagen.marketing --drop 2 --env dev --upload

Drop 1 is the baseline. About 20% of customers have a postal address that
disagrees with the CRM (marketing newer for half of them, older for the rest).
Each later drop flips consent for ~8% of customers, changes the preferred
channel for ~8% and changes the address for ~5%, so the reconciliation rules
are exercised repeatedly.
"""

import argparse
import csv
import datetime as dt
import random
from pathlib import Path

from datagen.common import (
    CHANNELS,
    build_customers,
    iso_utc,
    random_address,
    raw_bucket_name,
    upload_file,
)

MARKETING_COLUMNS = [
    "customer_id",
    "marketing_opt_in",
    "preferred_channel",
    "postal_address",
    "updated_at",
]


def baseline_state():
    rng = random.Random("marketing-baseline")
    state = {}
    for customer in build_customers():
        address = customer["postal_address"]
        updated_at = customer["updated_at"]
        if rng.random() < 0.20:
            address = random_address(rng)
            shift = dt.timedelta(days=rng.randint(1, 20))
            updated_at = updated_at + shift if rng.random() < 0.5 else updated_at - shift
        else:
            updated_at = updated_at - dt.timedelta(days=rng.randint(0, 5))
        state[customer["customer_id"]] = {
            "customer_id": customer["customer_id"],
            "marketing_opt_in": rng.random() < 0.6,
            "preferred_channel": rng.choice(CHANNELS),
            "postal_address": address,
            "updated_at": updated_at,
        }
    return state


def generate_marketing(drop):
    """All rows of the marketing snapshot for the given drop number (1, 2, 3, ...)."""
    if drop < 1:
        raise ValueError("drop must be 1 or higher")
    state = baseline_state()
    for k in range(2, drop + 1):
        rng = random.Random(f"marketing-drop-{k}")
        changed_at = dt.datetime(2026, 2, 1, 9, 0, 0) + dt.timedelta(days=7 * k)
        for customer_key in sorted(state):
            row = state[customer_key]
            roll = rng.random()
            if roll < 0.08:
                row["marketing_opt_in"] = not row["marketing_opt_in"]
                row["updated_at"] = changed_at
            elif roll < 0.16:
                row["preferred_channel"] = rng.choice(CHANNELS)
                row["updated_at"] = changed_at
            elif roll < 0.21:
                row["postal_address"] = random_address(rng)
                row["updated_at"] = changed_at
    rows = []
    for customer_key in sorted(state):
        row = state[customer_key]
        rows.append(
            {
                "customer_id": row["customer_id"],
                "marketing_opt_in": "true" if row["marketing_opt_in"] else "false",
                "preferred_channel": row["preferred_channel"],
                "postal_address": row["postal_address"],
                "updated_at": iso_utc(row["updated_at"]),
            }
        )
    return rows


def write_csv(path, rows):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=MARKETING_COLUMNS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    return path


def main(argv=None):
    parser = argparse.ArgumentParser(description="Generate a marketing list snapshot")
    parser.add_argument("--drop", type=int, default=1, help="Drop number (1 = baseline)")
    parser.add_argument("--env", default="dev", choices=["dev", "prod"])
    parser.add_argument("--out-dir", default="out")
    parser.add_argument("--upload", action="store_true", help="Upload to the raw bucket")
    args = parser.parse_args(argv)

    rows = generate_marketing(args.drop)
    filename = f"marketing_drop_{args.drop:03d}.csv"
    path = write_csv(Path(args.out_dir) / filename, rows)
    print(f"Wrote {len(rows)} rows to {path}")

    if args.upload:
        upload_file(path, raw_bucket_name(args.env), f"marketing/{filename}")


if __name__ == "__main__":
    main()
