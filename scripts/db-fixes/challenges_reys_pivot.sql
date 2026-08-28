-- Run in Supabase SQL editor.
-- Pivot away from repeated/daily Reys spending inside a challenge. New model:
-- joining a challenge costs a one-time 100 Reys entry fee; after that, nothing
-- else inside that challenge costs Reys (chl_buy_streak_freeze below goes back
-- to free — it just requires membership now, same as before it had a cost).
--
-- Creating a challenge still auto-joins the creator for free (that's not
-- "joining" someone else's challenge) — chlSubmitCreate's direct insert into
-- challenge_participants keeps working because the replacement RLS policy
-- below still allows a creator to insert their own row directly. Everyone
-- else must go through chl_join_challenge(), which is the only path that can
-- actually debit Reys, so a client can't bypass the fee by calling
-- .from('challenge_participants').insert(...) directly like before.

drop policy if exists "challenge_participants_insert_own" on challenge_participants;
create policy "challenge_participants_insert_creator_only" on challenge_participants
  for insert with check (
    auth.uid() = user_id
    and exists (select 1 from challenges where id = challenge_id and creator_id = auth.uid())
  );

create or replace function chl_join_challenge(p_challenge_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_creator_id uuid;
  v_balance integer;
  v_cost integer := 100;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;

  select creator_id into v_creator_id from challenges where id = p_challenge_id;
  if v_creator_id is null then raise exception 'Challenge not found'; end if;

  if exists (select 1 from challenge_participants where challenge_id=p_challenge_id and user_id=v_uid) then
    raise exception 'Already joined';
  end if;

  -- Creator joining their own challenge (e.g. the auto-join path failed earlier) is free.
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
  return v_balance;
end;
$$;

grant execute on function chl_join_challenge(uuid) to authenticated;

-- Streak Freeze is now a free member perk (the 100 Reys entry fee already paid for it) —
-- same guards as before, just no balance check/debit.
create or replace function chl_buy_streak_freeze(p_challenge_id uuid, p_freeze_date date)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_balance integer;
  v_inserted boolean;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;
  if not exists (select 1 from challenge_participants where challenge_id=p_challenge_id and user_id=v_uid) then
    raise exception 'Must be a member of this challenge';
  end if;
  if p_freeze_date < current_date then
    raise exception 'Cannot freeze a past date';
  end if;
  if exists (
    select 1 from posts
    where challenge_id=p_challenge_id and user_id=v_uid and category='progress'
      and created_at::date = p_freeze_date
  ) then
    raise exception 'Already logged progress that day';
  end if;

  insert into challenge_streak_freezes(challenge_id,user_id,freeze_date)
    values (p_challenge_id,v_uid,p_freeze_date)
    on conflict (challenge_id,user_id,freeze_date) do nothing;
  get diagnostics v_inserted = row_count;
  if not v_inserted then
    raise exception 'That day is already frozen';
  end if;

  select reys_balance into v_balance from profiles where id=v_uid;
  return coalesce(v_balance,0);
end;
$$;

grant execute on function chl_buy_streak_freeze(uuid,date) to authenticated;
