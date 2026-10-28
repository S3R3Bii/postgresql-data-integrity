-- Window query: best-so-far includes the initial loss, so deterioration
-- never becomes negative improvement. Ties have deterministic step order.
ANALYZE sql_proof.run;
ANALYZE sql_proof.checkpoint;
WITH trajectory AS (
  SELECT r.run_id,c.step,c.loss,
    LEAST(r.initial_loss,MIN(c.loss) OVER (
      PARTITION BY r.run_id ORDER BY c.step
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)) AS best_so_far
  FROM sql_proof.run r JOIN sql_proof.checkpoint c USING(run_id)
  WHERE r.batch_id='synthetic-v1'
), deltas AS (
  SELECT *,best_so_far-LAG(best_so_far) OVER (
    PARTITION BY run_id ORDER BY step) AS best_loss_change
  FROM trajectory
)
SELECT * FROM deltas ORDER BY run_id,step;

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM sql_proof.summary('synthetic-v1');

EXPLAIN (ANALYZE, BUFFERS)
WITH trajectory AS (
  SELECT r.run_id,c.step,c.loss,
    LEAST(r.initial_loss,MIN(c.loss) OVER (
      PARTITION BY r.run_id ORDER BY c.step
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)) AS best_so_far
  FROM sql_proof.run r JOIN sql_proof.checkpoint c USING(run_id)
  WHERE r.batch_id='synthetic-v1'
), deltas AS (
  SELECT *,best_so_far-LAG(best_so_far) OVER (
    PARTITION BY run_id ORDER BY step) AS best_loss_change
  FROM trajectory
)
SELECT * FROM deltas ORDER BY run_id,step;
