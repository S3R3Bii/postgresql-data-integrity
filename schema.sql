-- Dedicated exercise schema. Requires PostgreSQL 11+; no extensions.
CREATE SCHEMA IF NOT EXISTS sql_proof;
CREATE TABLE IF NOT EXISTS sql_proof.batch (
  batch_id text PRIMARY KEY CHECK (batch_id <> ''),
  payload jsonb NOT NULL,
  loaded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
-- Grain: one synthetic optimizer run; objective is minimized.
CREATE TABLE IF NOT EXISTS sql_proof.run (
  run_id text PRIMARY KEY,
  batch_id text NOT NULL REFERENCES sql_proof.batch,
  method text NOT NULL CHECK (method <> ''),
  budget numeric NOT NULL CHECK (budget >= 0),
  initial_loss numeric NOT NULL CHECK (initial_loss >= 0)
);
-- Grain: one numbered checkpoint per run. Budget is a run allocation,
-- not checkpoint elapsed time; zero allocation yields NULL efficiency.
CREATE TABLE IF NOT EXISTS sql_proof.checkpoint (
  run_id text NOT NULL REFERENCES sql_proof.run,
  step integer NOT NULL CHECK (step > 0),
  loss numeric NOT NULL CHECK (loss >= 0),
  PRIMARY KEY (run_id, step)
);

CREATE OR REPLACE PROCEDURE sql_proof.load_batch(p_batch_id text, p_payload jsonb)
LANGUAGE plpgsql AS $$
DECLARE prior jsonb;
BEGIN
  -- Serialize bounded exercise loaders, including concurrent replay.
  -- Lock and all writes belong to the caller's transaction; never COMMIT here.
  PERFORM pg_advisory_xact_lock(26010010);
  IF p_batch_id IS NULL OR p_batch_id = '' OR p_payload IS NULL
     OR jsonb_typeof(p_payload) <> 'object'
     OR jsonb_typeof(p_payload->'runs') IS DISTINCT FROM 'array'
     OR jsonb_typeof(p_payload->'checkpoints') IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'batch id and runs/checkpoints arrays required';
  END IF;
  IF jsonb_array_length(p_payload->'runs') > 1000
     OR jsonb_array_length(p_payload->'checkpoints') > 10000 THEN
    RAISE EXCEPTION 'bounded batch limit exceeded';
  END IF;
  SELECT payload INTO prior FROM sql_proof.batch WHERE batch_id = p_batch_id;
  IF FOUND THEN
    IF prior IS DISTINCT FROM p_payload THEN
      RAISE EXCEPTION 'batch id reused with different payload';
    END IF;
    RETURN; -- Exact JSONB replay: same keys, values and array order.
  END IF;
  -- Every checkpoint must refer to a run in THIS payload, not an earlier batch.
  IF EXISTS (
    SELECT 1 FROM jsonb_to_recordset(p_payload->'checkpoints') AS c(run_id text)
    WHERE NOT EXISTS (
      SELECT 1 FROM jsonb_to_recordset(p_payload->'runs') AS r(run_id text)
      WHERE r.run_id = c.run_id
    )
  ) THEN RAISE EXCEPTION 'checkpoint is orphaned from batch'; END IF;
  INSERT INTO sql_proof.batch(batch_id,payload) VALUES (p_batch_id,p_payload);
  INSERT INTO sql_proof.run
    SELECT r.run_id,p_batch_id,r.method,r.budget,r.initial_loss
    FROM jsonb_to_recordset(p_payload->'runs')
      AS r(run_id text,method text,budget numeric,initial_loss numeric);
  INSERT INTO sql_proof.checkpoint
    SELECT run_id,step,loss FROM jsonb_to_recordset(p_payload->'checkpoints')
      AS c(run_id text,step integer,loss numeric);
  -- Malformed types, missing values, duplicates and constraints raise errors.
  -- Unhandled errors roll back the complete CALL, including the batch row.
END $$;

CREATE OR REPLACE FUNCTION sql_proof.summary(p_batch_id text)
RETURNS TABLE(run_id text,method text,budget numeric,best_loss numeric,
              improvement numeric,improvement_per_budget numeric)
LANGUAGE sql STABLE AS $$
  SELECT r.run_id,r.method,r.budget,
         LEAST(r.initial_loss,COALESCE(MIN(c.loss),r.initial_loss)),
         r.initial_loss-LEAST(r.initial_loss,COALESCE(MIN(c.loss),r.initial_loss)),
         (r.initial_loss-LEAST(r.initial_loss,COALESCE(MIN(c.loss),r.initial_loss)))
           /NULLIF(r.budget,0)
  FROM sql_proof.run r LEFT JOIN sql_proof.checkpoint c USING(run_id)
  WHERE r.batch_id=p_batch_id
  GROUP BY r.run_id,r.method,r.budget,r.initial_loss
$$;
