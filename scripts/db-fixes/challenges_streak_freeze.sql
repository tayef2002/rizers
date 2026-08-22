-- Run in Supabase SQL editor.
-- "Streak Freeze" — spend 20 Reys to protect a day (today, or a future day
-- within the challenge) so a missed post doesn't break the streak. Modeled
-- on Duolingo's streak freeze: buy it in advance, it silently counts as a
-- kept day when the streak walker (chlComputeDayAndStreak, js/app.js)
-- checks that date and finds no real post.
--
-- No insert policy is granted to regular users on purpose — a freeze can
-- only be created via chl_buy_streak_freeze(), which debits Reys and
-- inserts the row atomically in the same transaction, so there's no way
-- for a client to insert a free freeze directly.

create table if not exists challenge_streak_freezes (
  id uuid primary key default gen_random_uuid(),
  challenge_id uuid not null references challenges(id) on delete cascade,
  user_id uuid not null references profiles(id),
  freeze_date date not null,
  created_at timestamptz not null default now(),
  unique(challenge_id, user_id, freeze_date)
);

alter table challenge_streak_freezes enable row level security;

drop policy if exists "select own streak freezes" on challenge_streak_freezes;
create policy "select own streak freezes" on challenge_streak_freezes
  for select using (auth.uid() = user_id);

create or replace function chl_buy_streak_freeze(p_challenge_id uuid, p_freeze_date date)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_balance integer;
  v_cost integer := 20;
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

  select reys_balance into v_balance from profiles where id=v_uid for update;
  if coalesce(v_balance,0) < v_cost then
    raise exception 'Not enough Reys';
  end if;

  insert into challenge_streak_freezes(challenge_id,user_id,freeze_date)
    values (p_challenge_id,v_uid,p_freeze_date)
    on conflict (challenge_id,user_id,freeze_date) do nothing;
  get diagnostics v_inserted = row_count;
  if not v_inserted then
    raise exception 'That day is already frozen';
  end if;

  update profiles set reys_balance = reys_balance - v_cost where id=v_uid returning reys_balance into v_balance;
  return v_balance;
end;
$$;

grant execute on function chl_buy_streak_freeze(uuid,date) to authenticated;
