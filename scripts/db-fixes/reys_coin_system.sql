-- Run in Supabase SQL editor.
-- Supersedes the subscription-expiry trigger from subscription_payments.sql
-- (run earlier this session) with the real plan: Reys is a credit/coin
-- currency, not a subscription clock. Some features stay free for everyone;
-- others cost Reys. Everyone gets 300 free Reys/day (claimed via a popup ->
-- Subscription page), and can buy more on top of that. Pricing for "buy
-- more" isn't decided yet, so approval stays manual and the admin sets how
-- many Reys a given payment is worth at approval time (reys_to_grant) —
-- same manual-verification shape as before, just crediting coins instead of
-- extending a subscription date.
--
-- "Reys" and the Rewards page's old "Rizers Coin (RZC)" are the same
-- currency (confirmed with the user — naming was just inconsistent). This
-- is the one real, server-side balance both pages should read from now.

alter table profiles add column if not exists reys_balance integer not null default 0;
alter table profiles add column if not exists last_reys_claim_date date;

-- Atomic daily-claim RPC — must run server-side (security definer) so a
-- user can't just increment their own balance from devtools. auth.uid()
-- is resolved from the caller's JWT, not a client-supplied id, and the
-- row lock (for update) prevents a double-click double-claiming the day.
create or replace function claim_daily_reys()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_last date;
  v_balance integer;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;
  select last_reys_claim_date, reys_balance into v_last, v_balance
    from profiles where id = v_uid for update;
  if v_last = current_date then
    raise exception 'Already claimed today';
  end if;
  update profiles set reys_balance = coalesce(reys_balance,0) + 300, last_reys_claim_date = current_date
    where id = v_uid
    returning reys_balance into v_balance;
  return v_balance;
end;
$$;

grant execute on function claim_daily_reys() to authenticated;

-- Column the admin fills in when approving a "buy more Reys" claim — how
-- many Reys this particular payment is worth. Nullable/unenforced until
-- approval time, since pricing isn't fixed yet and may vary per claim.
alter table subscription_payments add column if not exists reys_to_grant integer;

-- What the client-side price calculator told the user they'd get (tier
-- pick or custom-amount calculation) — purely informational for the admin
-- to cross-check against reys_to_grant before approving; never auto-applied.
alter table subscription_payments add column if not exists reys_requested integer;

create or replace function sp_activate_on_approval()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    if new.reys_to_grant is null or new.reys_to_grant <= 0 then
      raise exception 'Set reys_to_grant to a positive number before approving';
    end if;
    new.reviewed_at = now();
    update profiles
      set reys_balance = coalesce(reys_balance,0) + new.reys_to_grant
      where id = new.user_id;
  end if;
  return new;
end;
$$;
-- Trigger itself (sp_activate_on_approval_trg on subscription_payments,
-- created in subscription_payments.sql) is unchanged — replacing the
-- function body above is enough to swap its behavior.
