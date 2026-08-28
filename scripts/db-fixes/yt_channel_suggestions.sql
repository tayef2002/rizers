-- Run in Supabase SQL editor.
-- New table for the RizPlay "Suggestions" sub-tab: candidate channels found by
-- an admin-triggered YouTube search, waiting for a human approve/dismiss
-- decision. Nothing here is ever auto-approved — this only surfaces
-- candidates, same as the "paste a link" flow, just self-service on the
-- discovery step.

create table if not exists yt_channel_suggestions (
  channel_id text primary key,
  channel_title text,
  channel_photo text,
  channel_bio text,
  source_query text,
  discovered_at timestamptz not null default now(),
  dismissed boolean not null default false
);

alter table yt_channel_suggestions enable row level security;

drop policy if exists yt_channel_suggestions_admin_select on yt_channel_suggestions;
create policy yt_channel_suggestions_admin_select on yt_channel_suggestions
  for select using (is_admin());

drop policy if exists yt_channel_suggestions_admin_insert on yt_channel_suggestions;
create policy yt_channel_suggestions_admin_insert on yt_channel_suggestions
  for insert with check (is_admin());

drop policy if exists yt_channel_suggestions_admin_update on yt_channel_suggestions;
create policy yt_channel_suggestions_admin_update on yt_channel_suggestions
  for update using (is_admin()) with check (is_admin());

drop policy if exists yt_channel_suggestions_admin_delete on yt_channel_suggestions;
create policy yt_channel_suggestions_admin_delete on yt_channel_suggestions
  for delete using (is_admin());
