-- Run in Supabase SQL editor.
-- 1) video_reactions currently only supports a single "Inspire" toggle (video_id,user_id).
--    The Rise-feed suggested-video card now needs the same multi-emoji reaction picker real
--    posts use (Inspire/Respect/Dua/Wow/Support) — add a `type` column, default 'inspire' so
--    existing rows (and the RizPlay watch view's plain Inspire button) keep working unchanged.
alter table video_reactions add column if not exists type text default 'inspire';

-- One reaction per user per video (matches the existing 23505-duplicate-key handling in the
-- app) — safe to add even if some legacy duplicate rows exist, since the app already treats
-- 23505 as "already reacted" rather than an error.
create unique index if not exists video_reactions_video_user_key on video_reactions(video_id, user_id);

-- 2) New table for the suggested-video card's Comment button — mirrors the shape of a real
-- post's comments closely enough to reuse the same UI patterns.
create table if not exists video_comments (
  id uuid primary key default gen_random_uuid(),
  video_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  text text not null,
  created_at timestamptz not null default now()
);
create index if not exists video_comments_video_idx on video_comments(video_id, created_at);

alter table video_comments enable row level security;
-- Postgres has no "CREATE POLICY IF NOT EXISTS" (only CREATE TABLE/INDEX support IF NOT
-- EXISTS) — DROP + CREATE is the correct idempotent pattern for policies.
drop policy if exists "video_comments_select_all" on video_comments;
create policy "video_comments_select_all" on video_comments for select using (true);
drop policy if exists "video_comments_insert_own" on video_comments;
create policy "video_comments_insert_own" on video_comments for insert with check (auth.uid() = user_id);
