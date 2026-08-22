-- Run in Supabase SQL editor.
-- New social "Challenges" feature: users create a challenge, anyone can join it, and progress
-- posts made inside a challenge are just normal `posts` rows tagged with challenge_id — this
-- reuses the entire existing posts/comments/post_reactions stack unchanged.

create table if not exists challenges (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  description text,
  icon text not null default '🎯',
  duration_days integer,
  created_at timestamptz not null default now()
);

create table if not exists challenge_participants (
  id uuid primary key default gen_random_uuid(),
  challenge_id uuid not null references challenges(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  unique(challenge_id, user_id)
);

-- Nullable, no default → every existing posts row becomes challenge_id=NULL automatically
-- ("a normal community post") — fully backward compatible, zero data migration needed.
alter table posts add column if not exists challenge_id uuid references challenges(id) on delete cascade;
create index if not exists posts_challenge_id_idx on posts(challenge_id, created_at);

alter table challenges enable row level security;
drop policy if exists "challenges_select_all" on challenges;
create policy "challenges_select_all" on challenges for select using (true);
drop policy if exists "challenges_insert_own" on challenges;
create policy "challenges_insert_own" on challenges for insert with check (auth.uid() = creator_id);
drop policy if exists "challenges_update_own" on challenges;
create policy "challenges_update_own" on challenges for update using (auth.uid() = creator_id) with check (auth.uid() = creator_id);

alter table challenge_participants enable row level security;
-- Public select so anyone can see a challenge's member list/avatar strip/count, same as posts/post_reactions.
drop policy if exists "challenge_participants_select_all" on challenge_participants;
create policy "challenge_participants_select_all" on challenge_participants for select using (true);
-- Join = insert your own membership row.
drop policy if exists "challenge_participants_insert_own" on challenge_participants;
create policy "challenge_participants_insert_own" on challenge_participants for insert with check (auth.uid() = user_id);
-- Leave = delete your own membership row (same insert/delete-toggle shape as post_reactions).
drop policy if exists "challenge_participants_delete_own" on challenge_participants;
create policy "challenge_participants_delete_own" on challenge_participants for delete using (auth.uid() = user_id);

create index if not exists challenge_participants_challenge_idx on challenge_participants(challenge_id);
create index if not exists challenge_participants_user_idx on challenge_participants(user_id);
