-- Boop is one size at every level: a buddy has no stage. A Mac that still
-- sends one is taken, and its stage ignored (src/app.ts). Apply this after
-- the deploy that stops reading the column.

alter table buddies drop column stage;
