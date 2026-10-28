"""Deterministic synthetic fixture and independent Decimal oracle; stdlib only.

Commands: python companion.py prepare | check | run
run requires an already authorized local PostgreSQL database and psql on PATH.
Connection settings are inherited from libpq; never write credentials here.
"""
import csv
import json
import shutil
import subprocess
import sys
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def fixture():
    return {
        'runs': [
            {'run_id': 'r1', 'method': 'synthetic-a', 'budget': 10, 'initial_loss': 100},
            {'run_id': 'r2', 'method': 'synthetic-b', 'budget': 20, 'initial_loss': 100},
            {'run_id': 'r3', 'method': 'synthetic-zero', 'budget': 0, 'initial_loss': 50},
        ],
        'checkpoints': [
            {'run_id': 'r1', 'step': 1, 'loss': 80},
            {'run_id': 'r1', 'step': 2, 'loss': 60},
            {'run_id': 'r2', 'step': 1, 'loss': 90},
            {'run_id': 'r2', 'step': 2, 'loss': 60},
        ],
    }


def oracle(payload):
    rows = []
    for run in payload['runs']:
        best = min([run['initial_loss']] + [c['loss'] for c in payload['checkpoints']
                                           if c['run_id'] == run['run_id']])
        gain = Decimal(run['initial_loss']) - Decimal(best)
        rows.append(dict(run_id=run['run_id'], method=run['method'], budget=run['budget'],
                         best_loss=best, improvement=gain,
                         improvement_per_budget=gain / Decimal(run['budget'])
                         if run['budget'] else None))
    return rows


def prepare():
    payload = fixture()
    (ROOT / 'synthetic.json').write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
    sql = "CALL sql_proof.load_batch('synthetic-v1', $payload$" + json.dumps(payload)
    (ROOT / 'seed.sql').write_text(sql + '$payload$::jsonb);\n', encoding='utf-8')
    rows = oracle(payload)
    with (ROOT / 'expected_summary.csv').open('w', newline='', encoding='utf-8') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def check():
    payload = json.loads((ROOT / 'synthetic.json').read_text(encoding='utf-8'))
    assert payload == fixture(), 'fixture drift'
    assert len(payload['runs']) == 3 and len(payload['checkpoints']) == 4
    rows = oracle(payload)
    assert [r['improvement_per_budget'] for r in rows] == [Decimal(4), Decimal(2), None]
    assert [r['best_loss'] for r in rows] == [60, 60, 50]
    assert oracle({'runs': [], 'checkpoints': []}) == []
    # Deterioration cannot exceed the initial-loss baseline.
    worsening = {'runs': [payload['runs'][0]], 'checkpoints': [dict(run_id='r1', step=1, loss=200)]}
    assert oracle(worsening)[0]['improvement'] == 0
    with (ROOT / 'expected_summary.csv').open(encoding='utf-8', newline='') as stream:
        saved = list(csv.DictReader(stream))
    assert [r['improvement_per_budget'] for r in saved] == ['4', '2', '']
    notebook = json.loads((ROOT / 'companion.ipynb').read_text(encoding='utf-8'))
    assert notebook['nbformat'] == 4
    for cell in notebook['cells']:
        if cell['cell_type'] == 'code':
            compile(''.join(cell['source']), '<notebook>', 'exec')
    print('PASS: fixture counts; Decimal oracle; empty input; deterioration; CSV; notebook code syntax.')
    print('These are Python checks, not PostgreSQL execution.')


def run():
    psql = shutil.which('psql')
    if not psql:
        raise SystemExit('BLOCKED: psql absent. Need existing authorized local PostgreSQL 11+ and client.')
    # Explicit local transport only. PGPORT/PGDATABASE/PGUSER may configure an
    # existing database; -w prevents password prompts or credential collection.
    base = [psql, '-X', '-w', '-h', '127.0.0.1', '-v', 'ON_ERROR_STOP=1']
    with (ROOT / 'postgres_results.txt').open('w', encoding='utf-8') as log:
        for arguments in [
            ['-c', 'SELECT version(), current_database();'],
            ['-1', '-f', str(ROOT / 'schema.sql')],
            ['-1', '-f', str(ROOT / 'seed.sql')],
            ['-f', str(ROOT / 'tests.sql')],
            ['-f', str(ROOT / 'analysis.sql')],
        ]:
            result = subprocess.run(base + arguments, capture_output=True, text=True)
            log.write(result.stdout + result.stderr)
            log.flush()
            if result.returncode:
                raise SystemExit('PostgreSQL step failed; inspect postgres_results.txt. No success claim.')
    result = subprocess.run(base + ['-c',
        "COPY (SELECT * FROM sql_proof.summary('synthetic-v1') ORDER BY run_id) TO STDOUT CSV HEADER"],
        capture_output=True, text=True, check=True)
    (ROOT / 'actual_summary.csv').write_text(result.stdout, encoding='utf-8')
    actual = list(csv.DictReader(result.stdout.splitlines()))
    assert len(actual) == 3
    for got, expected in zip(actual, oracle(fixture())):
        for key, value in expected.items():
            if value is None:
                assert got[key] == ''
            elif isinstance(value, (int, Decimal)):
                assert Decimal(got[key]) == Decimal(value), (key, got, expected)
            else:
                assert got[key] == value
    with (ROOT / 'postgres_results.txt').open('a', encoding='utf-8') as log:
        log.write('\nPASS actual PostgreSQL CSV independently reconciled to Decimal oracle.\n')
    print('PASS PostgreSQL assertions and independently reconciled actual_summary.csv.')


if __name__ == '__main__':
    {'prepare': prepare, 'check': check, 'run': run}[sys.argv[1]]()
