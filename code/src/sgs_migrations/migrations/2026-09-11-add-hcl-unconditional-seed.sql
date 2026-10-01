-- Which blocks the walk seeds whatever the change is.
--
-- A [terraform_data] with [triggers_replace], and a [null_resource] with
-- [triggers], is replaced when the trigger's value moves.  Where that value is
-- not a function of the configuration -- [timestamp()] -- no edge can carry the
-- change, and the walk has to seed the block itself.
-- [Sg_tf_eval_replace_trigger] decides it at ingest, because the rule reads an
-- HCL expression and RFD 2172 refuses SQL that parses one.
-- [subgraph2/unconditional_seeds.sql] carries the rule and the measurement.
--
-- NULL is a third answer.  It means the row predates this column, and the walk
-- then seeds by the block's shape -- the rule this replaced, which is wider and
-- never narrower.  So the column is nullable with no default: a default would
-- make a legacy row indistinguishable from a block the ingest examined and
-- found safe.
alter table hcl
  add column unconditional_seed boolean;

-- The walk asks two questions of this column and the index answers both.
--
-- "Which blocks of this state must be seeded" is the first, and a partial index
-- answers it in the size of the answer rather than of the state.  "Did the
-- ingest that wrote this state know the column" is the second, and it is the
-- same index probed for a single row.
--
-- Partial on [is not null], and not on [is true].  The second question needs a
-- row that carries false to count.  Without it, a state whose every trigger is
-- safe reads as a legacy state and seeds all of them: Measured on a state of
-- 109 751 HCL nodes, that mistake is the difference between no seed and 8 668.
create index hcl_unconditional_seed_idx
  on hcl (state_id)
  where unconditional_seed is not null;
