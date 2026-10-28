# Public evidence review — 2026-10-01 UTC

Decision: suitable for a bounded, explicitly AI-assisted portfolio project.

Source and retained execution records are consistent: 11 SQL pass notices;
expected rejection SQLSTATEs; 1/3/4 retained batch/run/checkpoint counts;
4/2/NULL ratios; r1/r2 best-so-far values of 80→60 and 90→60.
CSV fields were reconciled to the independent Decimal reference during this
review. Notebook code cells match the original source, with counts 1–5 and
saved stdout. Core source was not modified.

Limits: this review did not rerun PostgreSQL, Jupyter, concurrency, load/scale,
or deployment tests. SQL input limits exist but boundary tests do not cover
every accepted/rejected form; non-finite values were not tested. Passing finite
synthetic fixtures does not establish unrestricted input validation.

The private manifest matched every listed file present in its ZIP; two listed
vendor-download support files were absent. They are irrelevant to SQL results
and are not carried into this public package or its fresh manifest.

Privacy: an allowlisted public copy excludes operational/installation/runtime
files. Absolute paths in retained SQL notices were replaced by [project]/ and
host references were removed from notebook prose. No credential literals were
found by the bounded pattern scan. Pattern scanning is not a universal secret
or privacy guarantee. Original private artifacts remain unchanged.

HTML preview is included. Browser visual inspection was not completed because
the cloud browser rejected the local preview URL. No screenshot or visual-QA
success is claimed.
