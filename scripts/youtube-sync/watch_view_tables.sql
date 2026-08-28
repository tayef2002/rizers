-- Run in Supabase SQL editor — adds the two tables the new RizPlay watch-view UI needs
-- (Inspire reaction + reflection notes). Both scoped to auth.users via RLS.

create table video_reactions (
  id uuid primary key default gen_random_uuid(),
  video_id text references yt_videos(video_id),
  user_id uuid references auth.users(id),
  created_at timestamptz default now(),
  unique(video_id, user_id)
);
alter table video_reactions enable row level security;
create policy "users insert own video reaction" on video_reactions for insert with check (auth.uid() = user_id);
create policy "public can read video reactions" on video_reactions for select using (true);

create table video_reflections (
  id uuid primary key default gen_random_uuid(),
  video_id text references yt_videos(video_id),
  user_id uuid references auth.users(id),
  note text not null,
  created_at timestamptz default now()
);
alter table video_reflections enable row level security;
create policy "users manage own reflections" on video_reflections
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
