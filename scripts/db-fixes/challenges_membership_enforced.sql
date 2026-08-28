-- Run in Supabase SQL editor.
-- The UI only hides the "Share your progress" composer trigger from non-members
-- (chlUpdateDetailJoinState() in js/app.js) — that's not a real guarantee, just a normal-use
-- convenience. Anyone authenticated could still call cmSubmitPost_sb(..., challengeId) directly
-- (e.g. from devtools) and insert a post tagged with a challenge_id they never joined, since the
-- existing posts INSERT policy only checks auth.uid() = user_id, nothing about challenge_id.
--
-- A BEFORE INSERT trigger (rather than editing the existing posts INSERT policy directly) is
-- used deliberately: it enforces this regardless of whatever that policy's exact definition is,
-- so there's no risk of loosening/breaking normal (non-challenge, challenge_id IS NULL) posting
-- by mis-replacing a policy this migration didn't create and doesn't need to know the name of.

create or replace function chl_enforce_post_membership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.challenge_id is not null then
    if not exists (
      select 1 from challenge_participants
      where challenge_id = new.challenge_id and user_id = new.user_id
    ) then
      raise exception 'Must be a member of this challenge to post in it';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists chl_enforce_post_membership_trg on posts;
create trigger chl_enforce_post_membership_trg
  before insert on posts
  for each row
  execute function chl_enforce_post_membership();
