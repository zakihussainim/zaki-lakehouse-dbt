"""Source 2: the CRM database (PostgreSQL on RDS) and its DMS change stream.

Run from the src folder, after the RDS + DMS stack is deployed:

    python -m datagen.crm --env dev init      # create the table and load 200 customers
    python -m datagen.crm --env dev start     # start the DMS full-load + CDC task
    python -m datagen.crm --env dev status    # show task status
    python -m datagen.crm --env dev mutate    # update, insert and delete customers (creates CDC events)

The database login is read from AWS Secrets Manager with your own AWS credentials,
so no password is ever stored in the repo or on disk.
"""

import argparse
import json
import random
import time

from datagen.common import (
    PROJECT,
    REGION,
    SEGMENTS,
    build_customers,
    customer_id,
    random_address,
    random_phone,
)

CREATE_TABLE_SQL = """
create table if not exists customers (
    customer_id    varchar(10) primary key,
    full_name      varchar(100) not null,
    email          varchar(200),
    phone          varchar(30),
    segment        varchar(20),
    postal_address varchar(300),
    updated_at     timestamp not null
)
"""

INSERT_SQL = """
insert into customers (customer_id, full_name, email, phone, segment, postal_address, updated_at)
values (%(customer_id)s, %(full_name)s, %(email)s, %(phone)s, %(segment)s, %(postal_address)s, %(updated_at)s)
on conflict (customer_id) do nothing
"""


def secret_name(env):
    return f"{PROJECT}-{env}-crm-credentials"


def task_id(env):
    return f"{PROJECT}-{env}-crm-customers"


def plan_mutations(existing_ids, rng, n_update=15, n_insert=5, n_delete=3):
    """Decide which customers to update, insert and delete. Pure, so it is unit tested."""
    ids = sorted(existing_ids)
    chosen = rng.sample(ids, k=min(len(ids), n_update + n_delete))
    to_delete = chosen[:n_delete]
    to_update = chosen[n_delete:]
    highest = max(int(i[1:]) for i in ids) if ids else 0
    to_insert = []
    for offset in range(1, n_insert + 1):
        n = highest + offset
        to_insert.append(
            {
                "customer_id": customer_id(n),
                "full_name": f"New Customer {n}",
                "email": f"new.customer{n}@example.com",
                "phone": random_phone(rng),
                "segment": rng.choice(SEGMENTS),
                "postal_address": random_address(rng),
            }
        )
    return {"update": to_update, "delete": to_delete, "insert": to_insert}


def connect(env):
    import boto3
    import psycopg2

    secret = boto3.client("secretsmanager", region_name=REGION).get_secret_value(
        SecretId=secret_name(env)
    )
    creds = json.loads(secret["SecretString"])
    return psycopg2.connect(
        host=creds["host"],
        port=creds["port"],
        dbname=creds["dbname"],
        user=creds["username"],
        password=creds["password"],
        sslmode="require",
        connect_timeout=10,
    )


def cmd_init(env):
    customers = build_customers()
    conn = connect(env)
    with conn, conn.cursor() as cur:
        cur.execute(CREATE_TABLE_SQL)
        for row in customers:
            cur.execute(INSERT_SQL, row)
    conn.close()
    print(f"customers table ready, {len(customers)} base customers loaded.")


def cmd_mutate(env):
    rng = random.Random()  # not seeded: every run produces new changes
    conn = connect(env)
    with conn, conn.cursor() as cur:
        cur.execute("select customer_id from customers")
        existing = [r[0] for r in cur.fetchall()]
        plan = plan_mutations(existing, rng)

        for cid in plan["update"]:
            cur.execute(
                """
                update customers
                set phone = %s,
                    segment = %s,
                    postal_address = %s,
                    updated_at = (now() at time zone 'utc')
                where customer_id = %s
                """,
                (random_phone(rng), rng.choice(SEGMENTS), random_address(rng), cid),
            )
        for row in plan["insert"]:
            cur.execute(INSERT_SQL.replace("%(updated_at)s", "(now() at time zone 'utc')"), row)
        for cid in plan["delete"]:
            cur.execute("delete from customers where customer_id = %s", (cid,))
    conn.close()
    print(
        f"Updated {len(plan['update'])}, inserted {len(plan['insert'])}, "
        f"deleted {len(plan['delete'])} customers."
    )


def _dms():
    import boto3

    return boto3.client("dms", region_name=REGION)


def _find_task(env):
    tasks = _dms().describe_replication_tasks(
        Filters=[{"Name": "replication-task-id", "Values": [task_id(env)]}]
    )["ReplicationTasks"]
    if not tasks:
        raise SystemExit(f"DMS task {task_id(env)} not found. Is enable_crm_cdc = true and applied?")
    return tasks[0]


def cmd_status(env):
    task = _find_task(env)
    print(f"Task {task['ReplicationTaskIdentifier']}: {task['Status']}")
    stats = task.get("ReplicationTaskStats", {})
    for key in ("FullLoadProgressPercent", "TablesLoaded", "TablesErrored"):
        if key in stats:
            print(f"  {key}: {stats[key]}")
    if task.get("LastFailureMessage"):
        print(f"  LastFailureMessage: {task['LastFailureMessage']}")


def cmd_start(env):
    task = _find_task(env)
    status = task["Status"]
    if status == "running":
        print("Task is already running.")
        return
    start_type = "start-replication" if status in ("ready", "creating") else "resume-processing"
    _dms().start_replication_task(
        ReplicationTaskArn=task["ReplicationTaskArn"],
        StartReplicationTaskType=start_type,
    )
    print(f"Start requested ({start_type}). Checking status in 30 seconds...")
    time.sleep(30)
    cmd_status(env)


COMMANDS = {
    "init": cmd_init,
    "mutate": cmd_mutate,
    "start": cmd_start,
    "status": cmd_status,
}


def main(argv=None):
    parser = argparse.ArgumentParser(description="Manage the CRM source database and DMS task")
    parser.add_argument("--env", default="dev", choices=["dev", "prod"])
    parser.add_argument("command", choices=sorted(COMMANDS))
    args = parser.parse_args(argv)
    COMMANDS[args.command](args.env)


if __name__ == "__main__":
    main()
