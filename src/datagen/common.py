"""Shared, deterministic reference data for the generators.

Every run produces the same base customers, so the CRM database and the
marketing files describe the same people and can disagree in controlled ways.
boto3 is imported lazily so the pure functions can be tested without AWS.
"""

import datetime as dt
import random

PROJECT = "zaki-lakehouse-dbt"
REGION = "eu-west-2"
N_CUSTOMERS = 200
BASE_SEED = 42
CRM_BASE_DATE = dt.datetime(2026, 1, 1, 9, 0, 0)

# Columns of the customers table in the CRM database (and in the DMS output).
CRM_COLUMNS = [
    "customer_id",
    "full_name",
    "email",
    "phone",
    "segment",
    "postal_address",
    "updated_at",
]

FIRST_NAMES = [
    "Amelia", "Oliver", "Isla", "Noah", "Ava", "Arthur", "Mia", "Leo", "Grace",
    "Oscar", "Freya", "Harry", "Ivy", "Jack", "Willow", "George", "Lily", "Theo",
    "Sophia", "Archie", "Ella", "Henry", "Rosie", "Alfie", "Poppy", "Charlie",
]
LAST_NAMES = [
    "Smith", "Jones", "Taylor", "Brown", "Williams", "Wilson", "Johnson", "Davies",
    "Patel", "Robinson", "Wright", "Thompson", "Evans", "Walker", "White", "Roberts",
    "Green", "Hall", "Wood", "Jackson", "Clarke", "Khan", "Lewis", "Hughes",
]
STREETS = [
    "High Street", "Station Road", "Church Lane", "Park Avenue", "Victoria Road",
    "Green Lane", "Manor Road", "Queens Road", "King Street", "Mill Lane",
]
CITIES = ["London", "Manchester", "Birmingham", "Leeds", "Glasgow", "Bristol", "Sheffield"]
POSTCODE_AREAS = ["E1", "M1", "B2", "LS1", "G1", "BS1", "S1"]
LETTERS = "ABDEFGHJLNPQRSTUWXYZ"

SEGMENTS = ["Consumer", "SMB", "Enterprise"]
CHANNELS = ["email", "sms", "post", "none"]


def customer_id(n):
    return f"C{n:04d}"


def random_address(rng):
    number = rng.randint(1, 220)
    street = rng.choice(STREETS)
    city = rng.choice(CITIES)
    area = rng.choice(POSTCODE_AREAS)
    postcode = f"{area} {rng.randint(1, 9)}{rng.choice(LETTERS)}{rng.choice(LETTERS)}"
    return f"{number} {street}, {city}, {postcode}"


def random_phone(rng):
    return f"+44 7{rng.randint(100, 999)} {rng.randint(100000, 999999)}"


def build_customers(n=N_CUSTOMERS, seed=BASE_SEED):
    """The base CRM customers. Identical on every call."""
    rng = random.Random(seed)
    customers = []
    for i in range(1, n + 1):
        first = rng.choice(FIRST_NAMES)
        last = rng.choice(LAST_NAMES)
        customers.append(
            {
                "customer_id": customer_id(i),
                "full_name": f"{first} {last}",
                "email": f"{first}.{last}{i}@example.com".lower(),
                "phone": random_phone(rng),
                "segment": rng.choices(SEGMENTS, weights=[6, 3, 1])[0],
                "postal_address": random_address(rng),
                "updated_at": CRM_BASE_DATE
                + dt.timedelta(days=rng.randint(0, 30), minutes=rng.randint(0, 600)),
            }
        )
    return customers


def iso_utc(ts):
    return ts.strftime("%Y-%m-%dT%H:%M:%SZ")


def raw_bucket_name(env):
    """Raw bucket name, built from the account of the current AWS login."""
    import boto3

    account = boto3.client("sts").get_caller_identity()["Account"]
    return f"{PROJECT}-{env}-raw-{account}"


def upload_file(local_path, bucket, key):
    import boto3

    boto3.client("s3", region_name=REGION).upload_file(str(local_path), bucket, key)
    print(f"Uploaded s3://{bucket}/{key}")
