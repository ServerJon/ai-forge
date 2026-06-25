---
name: create-alembic-migration
description: >-
  Create, review, and apply Alembic database migrations safely. Use this skill
  whenever the user changes a SQLAlchemy ORM model, adds/drops/renames a table or
  column, alters a type or enum, adds a constraint or index, or asks to "create a
  migration", "make a migration", "run a migration", "autogenerate", "alembic
  revision", "upgrade head", or "migrate the database" — even if they don't say
  the word "Alembic". Autogenerate is unreliable and ships broken migrations to
  production if applied unreviewed, so always use this skill to enforce the review
  checklist before applying.
user-invocable: false
---

# Create an Alembic Migration

Autogenerate is a starting point, not an answer. It silently omits `ondelete`,
mishandles enum changes, drops timezone awareness, and writes migrations that pass
on an empty dev database but fail against populated production data. This skill
enforces a generate → **review** → apply → verify loop so those failures are caught
before they ship.

## Prerequisites

Confirm these before generating anything. They prevent the most common review
failures downstream.

- **Database reachable.** Alembic connects to a live DB for autogenerate (it
  diffs models against the actual schema). Start it however the project does
  (e.g. `docker compose up -d db`, `make db-up`).
- **Models are imported by `env.py`.** Autogenerate only sees tables registered on
  the `target_metadata` that `env.py` exposes. If a new model isn't imported
  (directly or transitively), its table won't appear in the diff. Verify the
  import chain before blaming autogenerate for "missing" tables.
- **A naming convention is configured.** The metadata should define a
  `naming_convention` so constraints and indexes get deterministic names.
  Without it, autogenerate emits unnamed constraints that `downgrade()` can't
  reliably drop, and diffs churn between runs. Recommended baseline:

  ```python
  from sqlalchemy import MetaData

  NAMING_CONVENTION = {
      "ix": "ix_%(column_0_label)s",
      "uq": "uq_%(table_name)s_%(column_0_name)s",
      "ck": "ck_%(table_name)s_%(constraint_name)s",
      "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
      "pk": "pk_%(table_name)s",
  }
  metadata = MetaData(naming_convention=NAMING_CONVENTION)
  ```

  If it's missing, flag it to the user before proceeding — adding it later
  requires care because existing constraints keep their old names.
- **Single head.** Run `alembic heads`. If more than one head exists, resolve it
  (see Common Pitfalls) before creating a new revision, or you'll branch the chain.
- **Project conventions.** Respect whatever the project standardizes on. If the
  project documents these (a schema doc, model base class, etc.), read it first.
  Common ones worth checking: timezone-aware datetimes, PK strategy, enum naming,
  and default `ondelete` behavior per relationship type.

## Detect how the project invokes Alembic

Don't assume bare `alembic`. Check, in order, and use whichever applies:

- A project wrapper: `make migrate-create` / `make migrate` (grep the `Makefile`).
- A dependency-manager prefix: `poetry run alembic`, `pdm run alembic`,
  `uv run alembic`, or an activated venv with plain `alembic`.
- The config location: if `alembic.ini` isn't at the repo root, pass
  `-c path/to/alembic.ini`.

The commands below use bare `alembic` — prefix as the project requires.

## Steps

### 1. Name the change

Pick a short `snake_case` description in `<verb>_<object>` form, matching the
existing pattern in the `versions/` directory. The message becomes part of the
filename and the human-readable history, so make it specific.

Good: `add_orders_table`, `add_email_to_users`, `make_timestamps_tz_aware`,
`rename_status_enum_values`.
Avoid: `update`, `changes`, `fix_db`.

### 2. Generate the revision

```bash
alembic revision --autogenerate -m "<your_description>"
```

This writes a new file under `<script_location>/versions/<hash>_<msg>.py`.

For a migration with no model diff (e.g. a pure data migration or raw DDL), drop
`--autogenerate` to get an empty `upgrade`/`downgrade` scaffold to fill in by hand.

### 3. Review the generated file — required checklist

Open the file and verify every item. **This is the point of the skill — do not
skip it.** Autogenerate gets these wrong routinely.

- [ ] **Revision chain.** `down_revision` points at the head you actually intended.
      Re-run `alembic heads` to confirm there's still exactly one head.
- [ ] **No accidental drops.** Autogenerate diffs *all* metadata against the DB. If
      a model wasn't imported, or a table belongs to another service sharing the
      DB, it appears as a spurious `op.drop_table`/`op.drop_column`. Delete those
      ops — they will destroy data.
- [ ] **Foreign keys carry `ondelete`.** Autogenerate frequently omits it, leaving
      Postgres' default `NO ACTION`. Set it deliberately per the project's
      convention (e.g. `CASCADE` for owned/junction children, `RESTRICT` for
      master data, `SET NULL` for soft references).
- [ ] **NOT NULL columns added to populated tables.** A new `nullable=False` column
      with no default fails the instant any row exists — passes on an empty dev DB,
      breaks in prod. Either add a `server_default`, or add the column nullable →
      backfill in the migration body → `alter_column` to NOT NULL.
- [ ] **Enum changes.** Postgres enums (`sa.Enum(..., name=...)`) need a stable
      `name`. Autogenerate usually misses **renames and value changes** entirely:
      it can't `ALTER TYPE ... RENAME VALUE` portably, and adding a value can't run
      inside a transaction on older Postgres. Handle these with explicit
      `op.execute(...)` and verify the type lifecycle (create/alter/drop) by hand.
- [ ] **Type changes that lose or coerce data.** Any `op.alter_column(..., type_=)`
      may truncate or fail to cast existing rows. Add an explicit `USING` clause via
      `postgresql_using=` where needed, and confirm with the user before applying.
- [ ] **Datetime columns.** If the project standardizes on timezone-aware instants,
      verify `sa.DateTime(timezone=True)` (→ `TIMESTAMPTZ`), not naive `DateTime`.
- [ ] **Indexes.** Confirm an index exists for every FK and every column the app
      filters/sorts on. Autogenerate usually adds FK indexes but double-check.
- [ ] **SQLite targets need batch mode.** SQLite can't `ALTER`/`DROP` most things
      in place. Wrap such ops in `with op.batch_alter_table("t") as batch_op:`.
      Skip this for Postgres/MySQL.
- [ ] **`downgrade()` is real and reversible.** Verify it actually reverses
      `upgrade()` and drops what `upgrade()` created (named constraints included).
      If a true reverse is impossible (e.g. dropping an enum value with live rows),
      say so explicitly in the docstring rather than leaving a half-broken stub.

### 4. Dry-run (recommended for non-trivial migrations)

Render the SQL without touching the DB — fast way to catch a bad diff and the
exact statements that will run against prod:

```bash
alembic upgrade <down_revision>:<new_revision> --sql
```

### 5. Apply

```bash
alembic upgrade head
```

### 6. Verify

```bash
alembic current   # confirms head advanced to the new revision
alembic history   # spot-check the chain is linear and intact
```

For schema-level confirmation, inspect the live DB (an `information_schema` query
or `\d <table>`) rather than trusting that the migration "ran clean".

### 7. Update documentation

If the migration introduced, renamed, or dropped a table/column/enum, update any
schema doc or model reference the project keeps, so future sessions (human or
agent) don't drift from reality.

## Common Pitfalls

- **NOT NULL + no default on a populated table** → succeeds on empty dev DB, fails
  in prod. Use `server_default` or the nullable → backfill → NOT NULL pattern.
- **Renaming an enum value** → Postgres won't rename in place portably. Add the new
  value, migrate rows off the old one, then drop the old value. Autogenerate won't.
- **Adding a Postgres enum value inside a transaction** → fails on older Postgres.
  Run it outside the transaction (`op.execute` with autocommit, or a separate
  migration).
- **Missing `ondelete` on a junction-table FK** → orphan rows survive parent
  deletion. Set the intended `ondelete` explicitly.
- **Two heads** → someone created a parallel revision. Merge with
  `alembic merge -m "merge heads" <rev1> <rev2>`; never hand-edit `down_revision`
  to splice branches.
- **Async `env.py` + autogenerate** → the offline/online runners differ. Confirm
  `env.py` runs autogenerate through `connection.run_sync(...)`; otherwise the diff
  silently comes back empty against an async engine.
- **Spurious drops from a shared database** → if multiple apps share one DB,
  autogenerate proposes dropping the other app's tables. Scope `target_metadata`
  or use `include_object` in `env.py` to filter, and delete stray drops on review.

## Reference

- Existing migrations: the project's `versions/` directory — match their style.
- Config: `alembic.ini` and `env.py` (script location, `target_metadata`,
  naming convention, sync vs async runner, any `include_object` filters).
- Alembic operations reference: <https://alembic.sqlalchemy.org/en/latest/ops.html>
