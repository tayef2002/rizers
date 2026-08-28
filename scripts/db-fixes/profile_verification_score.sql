-- Run in Supabase SQL editor.
-- Profile-completeness scoring that unlocks the "verified" badge. Every editable profile
-- field earns points; a smaller "important" tier alone sums to 100 (the badge threshold),
-- a larger "optional" tier adds bonus score on top but never gates the badge. Recomputed
-- BEFORE INSERT/UPDATE on profiles itself (same shape as sp_activate_on_approval in
-- subscription_payments.sql) so the score/badge stay correct no matter which code path
-- wrote the row — the edit modal, the avatar upload flow, or any future one.

alter table profiles add column if not exists profile_completion_score integer not null default 0;
alter table profiles add column if not exists is_verified boolean not null default false;

-- null = follow the computed score (normal case). true/false = force is_verified regardless
-- of score — set only by hand in the Supabase table editor (never written by client code),
-- same convention as subscription_payments' manual "approved" flip. This is what protects
-- an already-verified account from being silently un-verified by an unrelated profiles
-- update (Reys claim, streak freeze purchase, etc.) before its own profile is complete.
alter table profiles add column if not exists is_verified_manual_override boolean;

create or replace function pf_recompute_completion()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_important int := 0;
  v_optional  int := 0;
  v_cat_filled boolean;
begin
  -- category holds either a plain string (main Edit Profile modal) or a JSON-stringified
  -- array like '["Blogger","Student"]' (inline About-section quick editor) — both count as
  -- filled; '' and '[]' (all selections cleared) do not.
  v_cat_filled := new.category is not null and btrim(new.category) not in ('', '[]');

  if new.avatar_url is not null and btrim(new.avatar_url) <> '' then v_important := v_important + 30; end if;
  if new.bio        is not null and btrim(new.bio)        <> '' then v_important := v_important + 15; end if;
  if v_cat_filled then v_important := v_important + 15; end if;
  if new.gender     is not null and btrim(new.gender)     <> '' then v_important := v_important + 10; end if;
  if new.city       is not null and btrim(new.city)       <> '' then v_important := v_important + 10; end if;
  if new.birthday   is not null                                 then v_important := v_important + 10; end if;
  if new.work       is not null and btrim(new.work)       <> '' then v_important := v_important + 10; end if;

  if new.hometown            is not null and btrim(new.hometown)            <> '' then v_optional := v_optional + 5; end if;
  if new.company             is not null and btrim(new.company)             <> '' then v_optional := v_optional + 5; end if;
  if new.education           is not null and btrim(new.education)          <> '' then v_optional := v_optional + 5; end if;
  if new.relationship_status is not null and btrim(new.relationship_status) <> '' then v_optional := v_optional + 5; end if;
  if new.goals               is not null and btrim(new.goals)               <> '' then v_optional := v_optional + 5; end if;
  if new.website             is not null and btrim(new.website)             <> '' then v_optional := v_optional + 5; end if;
  if new.youtube             is not null and btrim(new.youtube)             <> '' then v_optional := v_optional + 5; end if;
  if new.instagram           is not null and btrim(new.instagram)           <> '' then v_optional := v_optional + 5; end if;
  if new.madhhab             is not null and btrim(new.madhhab)             <> '' then v_optional := v_optional + 5; end if;
  if coalesce(new.quran_goal,0) > 0                                              then v_optional := v_optional + 5; end if;

  new.profile_completion_score := v_important + v_optional;
  new.is_verified := case
    when new.is_verified_manual_override is not null then new.is_verified_manual_override
    else (v_important >= 100)
  end;
  return new;
end;
$$;

drop trigger if exists pf_recompute_completion_trg on profiles;
create trigger pf_recompute_completion_trg
  before insert or update on profiles
  for each row
  execute function pf_recompute_completion();

-- Preserve the owner's existing manual grant (currently the only is_verified=true row) so
-- nothing changes for him today; he can fill in his own profile for a "real" badge later,
-- or clear the override any time with: update profiles set is_verified_manual_override = null where id = '...';
update profiles set is_verified_manual_override = true where is_verified = true;

-- Backfill profile_completion_score for every existing row by firing the new trigger once.
update profiles set bio = bio;
