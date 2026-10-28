# Transactional PostgreSQL proof project

Independent AI-assisted work, using invented data. Retained execution evidence
reports PostgreSQL 18.6 on 2026-10-01. This is a bounded portfolio demonstration,
not employment experience, production adoption or enterprise-scale evidence.

## What it demonstrates

- A transactional loading procedure with exact JSONB replay idempotency
- A reusable table-returning summary function
- CTEs, running minimum and LAG window analysis
- Duplicate/orphan rejection, failed-CALL rollback and explicit edge-case checks
- Database CSV reconciliation against a separate Python Decimal calculation

The fixture contains **3 runs and 4 checkpoints**. Ratios are **4, 2 and NULL**.
Retained logs record **11 passing SQL checks** and a repeated full pipeline with
**1 batch, 3 runs and 4 checkpoints** remaining. Tests roll back their temporary
rows. See `postgres_results.txt` for the actual test notices, trajectory values
and query plans; path prefixes alone have been redacted.

## Contract and limits

One run has one allocated budget, in invented units. Loss is minimized. Summary
improvement is the nonnegative best-observed reduction from initial loss divided
by the run allocation. Zero budget returns NULL; absent checkpoints use initial
loss. Empty/unknown batches return no summary rows.

`load_batch(batch_id, payload)` accepts runs/checkpoints arrays, bounded to 1,000
and 10,000 rows. Every checkpoint must reference a run in that same payload.
Types, required values, nonnegative-range checks, primary keys and foreign keys
constrain input. This is not a general-purpose JSON or finite-number validator:
extra keys are ignored on load but retained in replay identity, and PostgreSQL
may cast numeric strings. Non-finite-number rejection was not tested.

The same batch ID and exact JSONB payload is a no-op; changed payload and reused
run/checkpoint IDs are rejected. Array order matters; object key order does not.
This is exact replay, not an upsert. The procedure never commits; the caller owns
transactions. A transaction advisory lock serializes loaders for the example.
Concurrent-load behavior and throughput were not measured.

## Explore and reproduce

Open `companion.preview.html` for a portable walkthrough, or inspect
`companion.executed.ipynb`. The executed notebook retains five code cells run
sequentially with Python 3.10.11 in a shared namespace. It was **not executed by a
Jupyter kernel or nbclient**. No package installation is needed for Python checks.

From this folder:

```sh
python companion.py check
python reference_checks.py
```

These are Python/static checks, not a new database execution. To repeat SQL,
use an existing authorized, non-production local PostgreSQL database with psql
on PATH and normal libpq settings (`PGDATABASE`, `PGUSER`, optionally `PGPORT`).
Supply credentials through your normal secure local mechanism; do not save them
in this project. The runner forces IPv4 loopback and suppresses password prompts:

```sh
python companion.py prepare
python companion.py run
```

`run` creates the dedicated `sql_proof` schema if needed, seeds the fixture,
executes assertions, records query plans/timings, exports the real CSV and checks
it against the Decimal oracle. Rerunning overwrites the corresponding evidence
files in your copy. Use a disposable database. This package does not install,
start, reconfigure or stop a database server. A Jupyter notebook session is
optional and was not validated in this review.

## Evidence and public-copy handling

`actual_summary.csv` is the retained database export. `expected_summary.csv` is
the Python oracle; it must not be presented as a database result. The original
notebook pass measured 0.049 ms / 0.040 ms execution; the later repeated pipeline
measured 0.076 ms / 0.040 ms. These single tiny-fixture warm-cache observations
are diagnostic only and are not a speed or scale benchmark.

The public review checked source/evidence consistency, notebook structure and
syntax, fixture values, exact CSV reconciliation and retained test notices.
**PostgreSQL was not rerun during this review.** Original private artifacts were
preserved. This copy excludes host/user names, absolute host paths, installation
and lifecycle logs, runtime binaries, cluster data and credential-setup scripts.
Core SQL and Python source are byte-identical to the reviewed private package.
Notebook changes are limited to explanatory markdown/metadata and output path
redaction. A fresh `sha256_manifest.csv` describes this public package only.

## Explain the design

1. CALL loads rows; SELECT from the stable function returns a composable table
2. One run per run_id; one checkpoint per (run_id, step)
3. Exact replay does nothing; changed replay fails
4. A rejected checkpoint rolls back earlier writes in that CALL
5. r1 best-so-far is 80 then 60; another loss of 70 leaves it at 60
6. Zero budget yields NULL, rather than an invented efficiency

HTML preview is included. Browser visual inspection was not completed because
the cloud browser rejected the local preview URL. No screenshot or visual-QA
success is claimed.
