import csv
import datetime as dt
import random

from datagen import crm, marketing, orders
from datagen.common import N_CUSTOMERS, build_customers, customer_id


def test_base_customers_are_deterministic_and_unique():
    first = build_customers()
    second = build_customers()
    assert first == second
    assert len(first) == N_CUSTOMERS
    assert len({c["customer_id"] for c in first}) == N_CUSTOMERS
    assert len({c["email"] for c in first}) == N_CUSTOMERS


def test_orders_are_deterministic_per_day():
    day = dt.date(2026, 1, 5)
    assert orders.generate_orders(day, 100) == orders.generate_orders(day, 100)
    assert orders.generate_orders(day, 100) != orders.generate_orders(dt.date(2026, 1, 6), 100)


def test_orders_contain_unknown_customers_and_duplicates():
    rows = orders.generate_orders(dt.date(2026, 1, 5), 500)
    known = {customer_id(n) for n in range(1, N_CUSTOMERS + 1)}
    assert any(r["customer_id"] not in known for r in rows), "expected some orphan customers"
    ids = [r["order_id"] for r in rows]
    assert len(ids) > len(set(ids)), "expected some duplicate order rows"


def test_orders_csv_has_header_and_expected_columns(tmp_path=None):
    import tempfile
    from pathlib import Path

    folder = Path(tmp_path) if tmp_path else Path(tempfile.mkdtemp())
    path = orders.write_csv(folder / "orders.csv", orders.generate_orders(dt.date(2026, 1, 5), 20))
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.reader(handle)
        header = next(reader)
        rows = list(reader)
    assert header == orders.ORDER_COLUMNS
    assert all(len(r) == len(orders.ORDER_COLUMNS) for r in rows)


def test_marketing_drops_are_deterministic_and_change_over_time():
    drop1 = marketing.generate_marketing(1)
    assert drop1 == marketing.generate_marketing(1)
    assert len(drop1) == N_CUSTOMERS
    drop2 = marketing.generate_marketing(2)
    assert drop1 != drop2
    assert [r["customer_id"] for r in drop1] == [r["customer_id"] for r in drop2]


def test_marketing_baseline_disagrees_with_crm_for_some_customers():
    crm_addresses = {c["customer_id"]: c["postal_address"] for c in build_customers()}
    drop1 = marketing.generate_marketing(1)
    disagreements = [r for r in drop1 if r["postal_address"] != crm_addresses[r["customer_id"]]]
    assert 10 <= len(disagreements) <= 80


def test_marketing_rejects_drop_zero():
    try:
        marketing.generate_marketing(0)
    except ValueError:
        return
    raise AssertionError("expected ValueError")


def test_mutation_plan_counts_and_new_ids():
    existing = [customer_id(n) for n in range(1, N_CUSTOMERS + 1)]
    plan = crm.plan_mutations(existing, random.Random(1))
    assert len(plan["update"]) == 15
    assert len(plan["delete"]) == 3
    assert len(plan["insert"]) == 5
    assert not set(plan["update"]) & set(plan["delete"])
    new_ids = {row["customer_id"] for row in plan["insert"]}
    assert not new_ids & set(existing)
    assert customer_id(N_CUSTOMERS + 1) in new_ids
