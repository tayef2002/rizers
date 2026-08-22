-- Run in Supabase SQL editor.
-- A real transaction ledger for Reys — until now the only record of a balance
-- change was the new total itself (profiles.reys_balance); there was no log
-- of individual events, so there was nothing to show in a "history" list.
-- This adds one row per balance-changing event going forward (existing
-- balances are NOT backfilled — history starts from whenever this is run,
-- same as any real ledger only covering the period it's existed for).
--
-- Every insert happens inside the SAME security-definer function that
-- already changes reys_balance (claim_daily_reys, sp_activate_on_approval,
-- chl_join_challenge), so the ledger row and the balance change are always
-- atomic/consistent — never one without the other.

create table if not exists reys_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id),
  amount integer not null,       -- positive = credit, negative = debit
  balance_after integer not null,
  type text not null,            -- 'daily_claim' | 'purchase' | 'challenge_join'
  description text,
  created_at timestamptz not null default now()
);

alter table reys_transactions enable row level security;
drop policy if exists "select own reys transactions" on reys_transactions;
create policy "select own reys transactions" on reys_transactions
  for select using (auth.uid() = user_id);
-- No insert/update/delete policy for regular users on purpose — rows can only be
-- written by the security-definer functions below, which bypass RLS for their
-- own writes, so a client can't fabricate fake history entries.

create index if not exists reys_transactions_user_idx on reys_transactions(user_id, created_at desc);

grant select on reys_transactions to authenticated;

-- 1) Daily free claim — log the +300.
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
  insert into reys_transactions(user_id, amount, balance_after, type, description)
    values (v_uid, 300, v_balance, 'daily_claim', 'দৈনিক ফ্রি Reys');
  return v_balance;
end;
$$;

grant execute on function claim_daily_reys() to authenticated;

-- 2) bKash purchase approval — log the credit.
create or replace function sp_activate_on_approval()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_balance integer;
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    if new.reys_to_grant is null or new.reys_to_grant <= 0 then
      raise exception 'Set reys_to_grant to a positive number before approving';
    end if;
    new.reviewed_at = now();
    update profiles
      set reys_balance = coalesce(reys_balance,0) + new.reys_to_grant
      where id = new.user_id
      returning reys_balance into v_balance;
    insert into reys_transactions(user_id, amount, balance_after, type, description)
      values (new.user_id, new.reys_to_grant, coalesce(v_balance,0), 'purchase', 'bKash এ কেনা');
  end if;
  return new;
end;
$$;
-- Trigger itself (sp_activate_on_approval_trg on subscription_payments) is unchanged.

-- 3) Challenge join fee — log the -100 (only when it's actually charged; a
--    creator auto-/re-joining their own challenge is free, nothing to log).
create or replace function chl_join_challenge(p_challenge_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_creator_id uuid;
  v_title text;
  v_balance integer;
  v_cost integer := 100;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;

  select creator_id, title into v_creator_id, v_title from challenges where id = p_challenge_id;
  if v_creator_id is null then raise exception 'Challenge not found'; end if;

  if exists (select 1 from challenge_participants where challenge_id=p_challenge_id and user_id=v_uid) then
    raise exception 'Already joined';
  end if;

  if v_creator_id = v_uid then
    insert into challenge_participants(challenge_id, user_id) values (p_challenge_id, v_uid);
    select reys_balance into v_balance from profiles where id=v_uid;
    return coalesce(v_balance,0);
  end if;

  select reys_balance into v_balance from profiles where id=v_uid for update;
  if coalesce(v_balance,0) < v_cost then
    raise exception 'Not enough Reys';
  end if;

  insert into challenge_participants(challenge_id, user_id) values (p_challenge_id, v_uid);
  update profiles set reys_balance = reys_balance - v_cost where id=v_uid returning reys_balance into v_balance;
  insert into reys_transactions(user_id, amount, balance_after, type, description)
    values (v_uid, -v_cost, v_balance, 'challenge_join', coalesce(v_title, 'Challenge'));
  return v_balance;
end;
$$;

grant execute on function chl_join_challenge(uuid) to authenticated;
