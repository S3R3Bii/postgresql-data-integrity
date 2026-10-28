-- All assertions execute in a transaction rolled back at the end.
BEGIN;
DO $$
DECLARE p jsonb; n bigint; got numeric[];
BEGIN
  SELECT payload INTO STRICT p FROM sql_proof.batch WHERE batch_id='synthetic-v1';
  SELECT count(*) INTO n FROM sql_proof.checkpoint;
  CALL sql_proof.load_batch('synthetic-v1',p);
  IF (SELECT count(*) FROM sql_proof.checkpoint) <> n THEN
    RAISE EXCEPTION 'repeat-load changed checkpoint count'; END IF;
  RAISE NOTICE 'PASS exact replay idempotency';
  SELECT array_agg(improvement_per_budget ORDER BY run_id) INTO got
    FROM sql_proof.summary('synthetic-v1');
  IF got IS DISTINCT FROM ARRAY[4::numeric,2::numeric,NULL::numeric] THEN
    RAISE EXCEPTION 'independent hand calculation mismatch: %',got; END IF;
  RAISE NOTICE 'PASS function hand calculation and zero budget';
  IF NOT EXISTS (SELECT 1 FROM sql_proof.summary('synthetic-v1')
    WHERE run_id='r3' AND best_loss=50 AND improvement=0
      AND improvement_per_budget IS NULL) THEN
    RAISE EXCEPTION 'no-checkpoint initial-loss fallback failed'; END IF;
  RAISE NOTICE 'PASS no-checkpoint fallback';
  IF EXISTS(SELECT 1 FROM sql_proof.summary('missing')) THEN
    RAISE EXCEPTION 'unknown batch not empty'; END IF;
  CALL sql_proof.load_batch('test-empty','{"runs":[],"checkpoints":[]}');
  IF EXISTS(SELECT 1 FROM sql_proof.summary('test-empty')) THEN
    RAISE EXCEPTION 'empty batch not empty'; END IF;
  RAISE NOTICE 'PASS empty and unknown batch';
  SELECT array_agg(v ORDER BY step) INTO got FROM (
    SELECT c.step,LEAST(r.initial_loss,MIN(c.loss) OVER (ORDER BY c.step)) AS v
    FROM sql_proof.checkpoint c JOIN sql_proof.run r USING(run_id)
    WHERE r.run_id='r1') q;
  IF got IS DISTINCT FROM ARRAY[80::numeric,60::numeric] THEN
    RAISE EXCEPTION 'known window result mismatch'; END IF;
  RAISE NOTICE 'PASS known CTE/window result';
END $$;

-- Catch expected failures in PL/pgSQL subtransactions, then prove no partial writes.
CREATE FUNCTION pg_temp.expect_rejection(id text,p jsonb,wanted_state text DEFAULT 'P0001') RETURNS void
LANGUAGE plpgsql AS $$
DECLARE rejected boolean := false; b bigint; r bigint; c bigint; actual_state text;
BEGIN
  SELECT count(*) INTO b FROM sql_proof.batch;
  SELECT count(*) INTO r FROM sql_proof.run;
  SELECT count(*) INTO c FROM sql_proof.checkpoint;
  BEGIN
    CALL sql_proof.load_batch(id,p);
  EXCEPTION WHEN OTHERS THEN
    rejected := true;
    GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'expected rejection: %',id; END IF;
  IF actual_state IS DISTINCT FROM wanted_state THEN
    RAISE EXCEPTION 'wrong rejection state for %: expected %, got %',id,wanted_state,actual_state;
  END IF;
  IF (SELECT count(*) FROM sql_proof.batch)<>b
    OR (SELECT count(*) FROM sql_proof.run)<>r
    OR (SELECT count(*) FROM sql_proof.checkpoint)<>c THEN
    RAISE EXCEPTION 'failure left partial writes: %',id; END IF;
  RAISE NOTICE 'PASS rejection and rollback: % (SQLSTATE %)',id,actual_state;
END $$;
SELECT pg_temp.expect_rejection('test-orphan',
  '{"runs":[],"checkpoints":[{"run_id":"r1","step":9,"loss":1}]}');
SELECT pg_temp.expect_rejection('test-duplicate-run',
  '{"runs":[{"run_id":"new","method":"a","budget":1,"initial_loss":10},{"run_id":"new","method":"a","budget":1,"initial_loss":10}],"checkpoints":[]}', '23505');
SELECT pg_temp.expect_rejection('test-late-failure',
  '{"runs":[{"run_id":"new","method":"a","budget":1,"initial_loss":10}],"checkpoints":[{"run_id":"new","step":1,"loss":-1}]}', '23514');
SELECT pg_temp.expect_rejection('test-duplicate-checkpoint',
  '{"runs":[{"run_id":"new","method":"a","budget":1,"initial_loss":10}],"checkpoints":[{"run_id":"new","step":1,"loss":2},{"run_id":"new","step":1,"loss":3}]}', '23505');
SELECT pg_temp.expect_rejection('synthetic-v1','{"runs":[],"checkpoints":[]}');
SELECT pg_temp.expect_rejection('test-shape','{"runs":null,"checkpoints":[]}');
ROLLBACK;
