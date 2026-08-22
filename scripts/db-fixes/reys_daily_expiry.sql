-- Run in Supabase SQL editor.
-- The daily free 300 Reys now expire at the next midnight if unused,
-- instead of permanently adding to the purchased balance. Splits the
-- single reys_balance into two numbers:
--   reys_balance     — permanent, from approved bKash purchases only
--   daily_free_reys  — today's free claim, reset to 0 by the next claim
--                       regardless of leftover (no carry-over/stacking)
-- The client computes "reys_balance + daily_free_reys" as the spendable
-- total when last_reys_claim_date is today, and treats daily_free_reys as
-- already-expired (0) the moment that date isn't today anymore — no cron
-- job needed, since nothing reads a stale daily_free_reys as still valid.

alter table profiles add column if not exists daily_free_reys integer not null default 0;

create or replace function claim_daily_reys()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_last date;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;
  select last_reys_claim_date into v_last from profiles where id = v_uid for update;
  if v_last = current_date then
    raise exception 'Already claimed today';
  end if;
  -- Flat set, not increment — yesterday's unspent free Reys (if any) do
  -- not carry over, per the expiry rule above.
  update profiles set daily_free_reys = 300, last_reys_claim_date = current_date
    where id = v_uid;
  return 300;
end;
$$;
