-- Run in Supabase SQL editor.
--
-- PART 1 is an URGENT security fix, unrelated to the User Management feature
-- below it — found while researching schema for that feature. `profiles`,
-- `comments`, and `post_reactions` all still carry wide-open policies
-- (qual/with_check = true, no ownership check at all) that predate this
-- repo's tracked migration history — the same bug class as the `posts`
-- `allow_all` incident fixed earlier, just never caught on these three
-- tables. Right now ANY authenticated user (including the standing test
-- accounts) can set their own is_admin=true, credit themselves unlimited
-- Reys, or edit/delete any other user's profile, comment, or reaction.
--
-- PART 2 is the User Management feature: is_banned + a "simple block"
-- (writes blocked via RLS, no auth-level login block), plus an audited
-- Reys balance adjustment RPC for the admin panel.

/* ══════════════════════════════════════════════════════════════
   PART 1 — close the wide-open policies on profiles/comments/post_reactions
══════════════════════════════════════════════════════════════ */

-- is_banned needs to exist before the trigger below references it, in case
-- this file is ever re-run partially rather than as one full script.
alter table profiles add column if not exists is_banned boolean not null default false;

-- profiles: replace the wide-open allow_all/profiles_insert/profiles_update
-- with ownership-scoped ones. profiles_select (public read) is untouched —
-- that's an intentional, already-accepted design choice (see
-- profile_privacy_fields.sql), not part of this bug.
drop policy if exists allow_all on profiles;
drop policy if exists profiles_insert on profiles;
drop policy if exists profiles_update on profiles;

drop policy if exists profiles_insert_own on profiles;
create policy profiles_insert_own on profiles
  for insert with check (auth.uid() = id);

drop policy if exists profiles_update_own on profiles;
create policy profiles_update_own on profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists profiles_admin_update on profiles;
create policy profiles_admin_update on profiles
  for update using (is_admin()) with check (is_admin());

-- comments / post_reactions: the properly-scoped policies already sitting
-- next to allow_all ("Users can comment", "Users can react", "Users can
-- remove reaction", the *_select_all ones) cover every real feature in the
-- app — grepped js/app.js, there is no comment edit/delete UI at all, and
-- reactions already toggle via delete-then-insert using their own policies.
-- allow_all is pure dead-weight risk, safe to drop outright.
drop policy if exists allow_all on comments;
drop policy if exists allow_all on post_reactions;

-- Column-level guard: even with profiles locked to "own row only", a user
-- editing their own profile (name/bio/city/...) could still sneak
-- is_admin/is_banned/reys_balance into the same update payload — or even a
-- brand new signup row — since RLS only checks row ownership, not which
-- columns changed or were set. This fires on both INSERT and UPDATE.
--
-- Deliberately NOT security definer: current_user needs to reflect who's
-- REALLY calling, so this can tell a raw client request (PostgREST always
-- runs those as the 'authenticated' role) apart from a trusted context —
-- the security-definer RPCs below (claim_daily_reys, chl_join_challenge,
-- admin_adjust_reys), which already run as their owner role, and the
-- Supabase SQL editor / table editor (the established way is_admin and
-- is_verified_manual_override get hand-set, per admin_foundation.sql and
-- profile_verification_score.sql), which has no 'authenticated' role
-- either. Making THIS function security definer would collapse that
-- distinction — current_user would always equal its own owner, for every
-- caller, and the check below would never fire for anyone.
create or replace function profiles_protect_sensitive_columns()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user <> 'authenticated' or is_admin() then
    return new;
  end if;

  if TG_OP = 'INSERT' then
    if new.is_admin is true
       or new.is_banned is true
       or new.is_verified_manual_override is not null
       or coalesce(new.reys_balance, 0) <> 0
       or coalesce(new.daily_free_reys, 0) <> 0
       or new.last_reys_claim_date is not null
       or new.subscription_status is distinct from 'trial'
       or new.subscription_expires_at is not null
    then
      raise exception 'Not authorized to set this field';
    end if;
    return new;
  end if;

  if new.is_admin is distinct from old.is_admin
     or new.is_banned is distinct from old.is_banned
     or new.is_verified_manual_override is distinct from old.is_verified_manual_override
     or new.reys_balance is distinct from old.reys_balance
     or new.daily_free_reys is distinct from old.daily_free_reys
     or new.last_reys_claim_date is distinct from old.last_reys_claim_date
     or new.subscription_status is distinct from old.subscription_status
     or new.subscription_expires_at is distinct from old.subscription_expires_at
  then
    raise exception 'Not authorized to change this field';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_protect_sensitive_columns_trg on profiles;
create trigger profiles_protect_sensitive_columns_trg
  before insert or update on profiles
  for each row
  execute function profiles_protect_sensitive_columns();

/* ══════════════════════════════════════════════════════════════
   PART 2 — User Management: is_banned (simple block) + audited Reys adjust
══════════════════════════════════════════════════════════════ */

create or replace function is_banned() returns boolean
language sql security definer stable
set search_path = public
as $$ select coalesce((select is_banned from profiles where id = auth.uid()), false); $$;

-- Block a banned user's direct-insert writes app-wide (posts, comments,
-- reactions, reports). Re-declaring each policy with the same name replaces
-- its with_check in place.
drop policy if exists "Users can post" on posts;
create policy "Users can post" on posts
  for insert with check (auth.uid() = user_id and not is_banned());

drop policy if exists "Users can comment" on comments;
create policy "Users can comment" on comments
  for insert with check (auth.uid() = user_id and not is_banned());

drop policy if exists "Users can react" on post_reactions;
create policy "Users can react" on post_reactions
  for insert with check (auth.uid() = user_id and not is_banned());

drop policy if exists reports_insert_own on reports;
create policy reports_insert_own on reports
  for insert with check (auth.uid() = reporter_id and not is_banned());

drop policy if exists challenge_participants_insert_creator_only on challenge_participants;
create policy challenge_participants_insert_creator_only on challenge_participants
  for insert with check (
    auth.uid() = user_id
    and not is_banned()
    and exists (select 1 from challenges where id = challenge_id and creator_id = auth.uid())
  );

-- Most challenge joins go through this RPC (bypasses RLS as the function
-- owner), not the direct-insert policy above — needs its own ban check.
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
  if is_banned() then raise exception 'Account suspended'; end if;

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

-- NOTE: claim_daily_reys() is deliberately NOT touched here. Two earlier
-- migrations (reys_daily_expiry.sql and reys_transactions_ledger.sql)
-- redefined it differently — one against daily_free_reys (expiring), one
-- against reys_balance (permanent) — and which is actually live in
-- production has never been confirmed (see project memory / DueTasks.md).
-- js/app.js's daily-claim UI is built against the daily_free_reys contract.
-- Redefining this function again here, without first resolving that
-- ambiguity, risks silently picking the wrong model and corrupting the
-- Reys economy further. Known, deliberately deferred gap: a banned user
-- can still claim daily Reys until that's resolved separately.

-- Audited manual Reys balance adjustment for the admin panel — mirrors the
-- existing ledger pattern (sp_activate_on_approval/chl_join_challenge):
-- every balance change gets a matching reys_transactions row, atomically.
create or replace function admin_adjust_reys(p_user_id uuid, p_amount integer, p_description text default null)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_balance integer;
begin
  if not is_admin() then
    raise exception 'Not authorized';
  end if;
  if p_amount = 0 then
    raise exception 'Amount must be non-zero';
  end if;
  update profiles set reys_balance = coalesce(reys_balance,0) + p_amount
    where id = p_user_id
    returning reys_balance into v_balance;
  if v_balance is null then
    raise exception 'User not found';
  end if;
  if v_balance < 0 then
    raise exception 'Adjustment would result in a negative balance';
  end if;
  insert into reys_transactions(user_id, amount, balance_after, type, description)
    values (p_user_id, p_amount, v_balance, 'admin_adjustment', coalesce(p_description, 'Admin adjustment'));
  return v_balance;
end;
$$;

grant execute on function admin_adjust_reys(uuid, integer, text) to authenticated;
