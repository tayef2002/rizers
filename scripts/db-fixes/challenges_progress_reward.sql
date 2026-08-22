-- Run in Supabase SQL editor.
-- Rewards 15 Reys for the FIRST progress post logged in a given challenge
-- each day (extra posts the same day don't pay out again). Extends the
-- existing chl_enforce_post_membership() trigger (already fires on every
-- challenge-tagged post insert, already security-definer) rather than
-- adding a separate claimable RPC — since the reward is tied 1:1 to a real
-- post INSERT happening inside the same transaction, there's no separate
-- "claim" step a client could call repeatedly to farm free Reys.
-- 15 is a starting number, easy to change later — same order of magnitude
-- as the 15-25 Reys planned for other in-app actions.

create or replace function chl_enforce_post_membership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_already_rewarded_today boolean;
begin
  if new.challenge_id is not null then
    if not exists (
      select 1 from challenge_participants
      where challenge_id = new.challenge_id and user_id = new.user_id
    ) then
      raise exception 'Must be a member of this challenge to post in it';
    end if;

    if new.category = 'progress' then
      select exists(
        select 1 from posts
        where challenge_id = new.challenge_id
          and user_id = new.user_id
          and category = 'progress'
          and created_at::date = current_date
      ) into v_already_rewarded_today;
      if not v_already_rewarded_today then
        update profiles set reys_balance = coalesce(reys_balance,0) + 15 where id = new.user_id;
      end if;
    end if;
  end if;
  return new;
end;
$$;
-- Trigger itself (chl_enforce_post_membership_trg on posts, created in
-- challenges_membership_enforced.sql) is unchanged — replacing the function
-- body is enough.
