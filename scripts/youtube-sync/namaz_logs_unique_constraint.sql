-- Run in Supabase SQL editor — fixes a pre-existing bug: adult_namaz_logs had no unique
-- constraint on (user_id, prayer, date), so every upsert() call using
-- onConflict:'user_id,prayer,date' silently failed with "no unique or exclusion constraint
-- matching the ON CONFLICT specification" (error 42P10). This affects both the Namaz Tracker
-- page itself and the new Hadi feed card's "মার্ক করলাম" button.

-- If this fails with a duplicate-key error, there are already duplicate rows for the same
-- user/prayer/date — run the dedup block below first, then retry the constraint.
alter table adult_namaz_logs
  add constraint adult_namaz_logs_user_prayer_date_key unique (user_id, prayer, date);

-- Dedup (only run if the ALTER above fails) — keeps the most recently created row per
-- user/prayer/date, deletes the rest:
-- delete from adult_namaz_logs a using adult_namaz_logs b
--   where a.user_id = b.user_id and a.prayer = b.prayer and a.date = b.date
--   and a.created_at < b.created_at;
