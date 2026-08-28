-- Run in Supabase SQL editor — same class of bug as namaz_logs_unique_constraint.sql:
-- adult_sleep_logs has no unique constraint on (user_id, date_key), so every upsert() call
-- using onConflict:'user_id,date_key' silently fails with "no unique or exclusion constraint
-- matching the ON CONFLICT specification" (error 42P10). This affects the real Sleep Tracker
-- page's own save AND the new Sleep quick-log card in the Rise feed.

-- If this fails with a duplicate-key error, there are already duplicate rows for the same
-- user/date — run the dedup block below first, then retry the constraint.
alter table adult_sleep_logs
  add constraint adult_sleep_logs_user_date_key unique (user_id, date_key);

-- Dedup (only run if the ALTER above fails) — keeps the most recently created row per
-- user/date, deletes the rest:
-- delete from adult_sleep_logs a using adult_sleep_logs b
--   where a.user_id = b.user_id and a.date_key = b.date_key
--   and a.created_at < b.created_at;
