"""Offline integrity checks for the dbt project (no AWS or dbt install needed)."""

import re
from pathlib import Path

import yaml

DBT = Path(__file__).resolve().parents[1] / "dbt"
SQL_FILES = sorted((DBT / "models").rglob("*.sql")) + sorted((DBT / "tests").rglob("*.sql"))


def _model_names():
    return {p.stem for p in (DBT / "models").rglob("*.sql")}


def _source_tables():
    sources = yaml.safe_load((DBT / "models" / "staging" / "sources.yml").read_text(encoding="utf-8"))
    return {
        (source["name"], table["name"])
        for source in sources["sources"]
        for table in source["tables"]
    }


def test_every_ref_points_to_an_existing_model():
    models = _model_names()
    for path in SQL_FILES:
        for ref in re.findall(r"ref\(\s*'([^']+)'\s*\)", path.read_text(encoding="utf-8")):
            assert ref in models, f"{path.name} refs unknown model {ref}"


def test_every_source_points_to_a_declared_table():
    declared = _source_tables()
    for path in SQL_FILES:
        text = path.read_text(encoding="utf-8")
        for src, table in re.findall(r"source\(\s*'([^']+)'\s*,\s*'([^']+)'\s*\)", text):
            assert (src, table) in declared, f"{path.name} uses undeclared source {src}.{table}"


def test_every_source_table_is_a_terraform_raw_table():
    catalog = (DBT.parent / "terraform" / "modules" / "catalog" / "main.tf").read_text(encoding="utf-8")
    for _, table in _source_tables():
        assert f'resource "aws_glue_catalog_table" "{table}"' in catalog


def test_schema_yml_files_are_valid_and_reference_real_models():
    models = _model_names()
    for path in (DBT / "models").rglob("schema.yml"):
        doc = yaml.safe_load(path.read_text(encoding="utf-8"))
        for model in doc.get("models", []):
            assert model["name"] in models, f"{path} documents unknown model {model['name']}"


def test_jinja_blocks_are_balanced_in_every_sql_file():
    for path in SQL_FILES:
        text = path.read_text(encoding="utf-8")
        assert text.count("{{") == text.count("}}"), path.name
        assert text.count("{%") == text.count("%}"), path.name
        assert text.count("(") == text.count(")"), f"unbalanced parentheses in {path.name}"
