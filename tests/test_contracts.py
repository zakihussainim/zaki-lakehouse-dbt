"""Contract tests: the generators and the Terraform raw tables must agree on column names."""

import re
from pathlib import Path

from datagen.common import CRM_COLUMNS
from datagen.marketing import MARKETING_COLUMNS
from datagen.orders import ORDER_COLUMNS

CATALOG_TF = Path(__file__).resolve().parents[1] / "terraform" / "modules" / "catalog" / "main.tf"


def _tf_list(name):
    text = CATALOG_TF.read_text(encoding="utf-8")
    match = re.search(rf"{name}\s*=\s*\[(.*?)\]", text, re.S)
    assert match, f"{name} not found in {CATALOG_TF}"
    return re.findall(r'"([^"]+)"', match.group(1))


def _tf_map_keys(name):
    text = CATALOG_TF.read_text(encoding="utf-8")
    match = re.search(rf"{name}\s*=\s*\{{(.*?)\}}", text, re.S)
    assert match, f"{name} not found in {CATALOG_TF}"
    return re.findall(r"^\s*(\w+)\s*=", match.group(1), re.M)


def test_orders_columns_match_terraform():
    assert ORDER_COLUMNS == _tf_list("orders_columns")


def test_marketing_columns_match_terraform():
    assert MARKETING_COLUMNS == _tf_list("marketing_columns")


def test_crm_columns_match_terraform():
    assert set(_tf_map_keys("crm_columns")) == {"op", "cdc_ts", *CRM_COLUMNS}
