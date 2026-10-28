"""Read-only reference/evidence checks; does not connect to PostgreSQL."""
import csv
import json
import re
from decimal import Decimal
from pathlib import Path
import companion

root = Path(__file__).resolve().parent
payload = json.loads((root / 'synthetic.json').read_text())
assert payload == companion.fixture()
expected = companion.oracle(payload)
for name in ['actual_summary.csv', 'expected_summary.csv']:
    rows = list(csv.DictReader((root / name).open(newline='')))
    assert len(rows) == len(expected)
    for got, want in zip(rows, expected):
        assert set(got) == set(want)
        for key, value in want.items():
            if value is None:
                assert got[key] == ''
            elif isinstance(value, (int, Decimal)):
                assert Decimal(got[key]) == Decimal(value)
            else:
                assert got[key] == value
assert [r['improvement_per_budget'] for r in expected] == [Decimal(4), Decimal(2), None]
source = json.loads((root / 'companion.ipynb').read_text())
executed = json.loads((root / 'companion.executed.ipynb').read_text())
sc = [c for c in source['cells'] if c['cell_type'] == 'code']
ec = [c for c in executed['cells'] if c['cell_type'] == 'code']
assert source['nbformat'] == executed['nbformat'] == 4
assert len(sc) == len(ec) == 5
assert [c['source'] for c in sc] == [c['source'] for c in ec]
assert [c['execution_count'] for c in ec] == list(range(1, 6))
for c in ec:
    compile(''.join(c['source']), '<retained-notebook>', 'exec')
    assert all(o['output_type'] == 'stream' for o in c['outputs'])
log = (root / 'postgres_results.txt').read_text()
assert len(re.findall(r'NOTICE:  PASS', log)) == 11
assert '1 batch / 3 runs / 4 checkpoints' in log
for label, state in [('test-orphan','P0001'), ('test-duplicate-run','23505'),
                     ('test-late-failure','23514'), ('test-duplicate-checkpoint','23505'),
                     ('synthetic-v1','P0001'), ('test-shape','P0001')]:
    assert f'PASS rejection and rollback: {label} (SQLSTATE {state})' in log
assert 'PostgreSQL 18.6' in log
print('PASS: all CSV fields match Decimal reference; ratios 4 / 2 / NULL.')
print('PASS: 11 retained SQL notices, expected SQLSTATEs and retained 1/3/4 counts.')
print('PASS: five matching notebook code cells, ordered counts and code syntax.')
print('These are static/reference checks. PostgreSQL and Jupyter were not rerun.')
