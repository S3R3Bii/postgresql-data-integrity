# PostgreSQL data integrity and analytical queries

A repeatable research-data load should not double-count records or leave partial results after a failure. This project demonstrates that behavior with a transactional PostgreSQL loader, analytical SQL and checks against independent Python calculations.

The retained October 1, 2026 execution passed **11 SQL assertions**. Running the pipeline twice left **one batch, three runs and four checkpoints**. The exported analytical results matched hand calculations, including a zero-budget case that returns NULL.

This is an independent, AI-assisted portfolio project using fictional data. The fixture is deliberately small; it demonstrates correctness checks rather than database scale or production adoption.

## Start here

| Question | Evidence |
| --- | --- |
| How are valid, repeatable loads enforced? | [Schema and transactional procedure](schema.sql) |
| How are the research results queried? | [CTEs and window functions](analysis.sql) |
| What happens when a load fails? | [SQL assertions](tests.sql) and [retained execution log](postgres_results.txt) |
| Do the exported numbers reconcile? | [Independent reference checks](reference_checks.py) |
| How can I reproduce or inspect it? | [Notebook](companion.ipynb) and [technical notes](TECHNICAL_NOTES.md) |

## Run the reference checks

```sh
python companion.py check
python reference_checks.py
```

These commands need only Python's standard library. They compare retained database results with a Decimal calculation and inspect the recorded SQL checks and notebook structure. They do not rerun PostgreSQL. The technical notes describe how to repeat SQL in a disposable, authorized local database.

## Design decisions

- Exact repeated payloads are a no-op; changed payloads are rejected.
- A failed load rolls back its earlier writes.
- Zero budget returns NULL instead of an invented efficiency value.
- Window queries track best-so-far results and changes between checkpoints.

The next useful extension is to test concurrent loaders and realistic data volumes. Those results are not established by this example.

Created as part of [James Jean's data science portfolio](https://james-jean-data-science.s3r3bii.chatgpt.site). Source and execution history are documented in the technical notes.
