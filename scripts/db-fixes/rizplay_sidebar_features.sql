-- Run in Supabase SQL editor.
-- Powers a YouTube-style left sidebar on the consumer RizPlay page: browse by
-- category or channel, plus personal Watch History and Saved videos ("Liked
-- Videos" reuses the existing video_reactions table — no new table needed
-- there, it already records one reaction per user per video and is
-- publicly readable for the count shown on the watch view).

-- Category didn't exist anywhere on yt_channels/yt_videos before this —
-- admin_decide_channel() discarded the category chosen on the admin
-- Suggestions tab at approval time. Adding it here and threading it through
-- below is what makes the sidebar's category browsing possible.
alter table yt_channels add column if not exists category text;
alter table yt_videos add column if not exists category text;

-- Personal, not public — a user's watch history / saved list is their own.
create table if not exists video_watch_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  video_id text not null,
  watched_at timestamptz not null default now(),
  unique(user_id, video_id)
);
alter table video_watch_history enable row level security;
drop policy if exists video_watch_history_select_own on video_watch_history;
create policy video_watch_history_select_own on video_watch_history for select using (auth.uid() = user_id);
drop policy if exists video_watch_history_insert_own on video_watch_history;
create policy video_watch_history_insert_own on video_watch_history for insert with check (auth.uid() = user_id);
drop policy if exists video_watch_history_update_own on video_watch_history;
create policy video_watch_history_update_own on video_watch_history for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists video_watch_history_delete_own on video_watch_history;
create policy video_watch_history_delete_own on video_watch_history for delete using (auth.uid() = user_id);

create table if not exists video_saves (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  video_id text not null,
  created_at timestamptz not null default now(),
  unique(user_id, video_id)
);
alter table video_saves enable row level security;
drop policy if exists video_saves_select_own on video_saves;
create policy video_saves_select_own on video_saves for select using (auth.uid() = user_id);
drop policy if exists video_saves_insert_own on video_saves;
create policy video_saves_insert_own on video_saves for insert with check (auth.uid() = user_id);
drop policy if exists video_saves_delete_own on video_saves;
create policy video_saves_delete_own on video_saves for delete using (auth.uid() = user_id);

-- admin_decide_channel() gains an optional category param, stamped onto the
-- channel row and onto every newly-inserted video from it (a suggestion's
-- category is channel-level, so its videos inherit the same one). Existing
-- cascade behavior (only ever touching still-'pending' videos, never
-- overwriting an admin's individual approve/reject) is unchanged.
--
-- Adding a parameter changes the function's signature, so `create or
-- replace` would silently create a SECOND overload alongside the original
-- 6-argument version instead of replacing it — explicitly dropping the old
-- signature first avoids two ambiguous admin_decide_channel functions
-- existing at once (which breaks PostgREST's RPC resolution).
drop function if exists admin_decide_channel(text, text, text, text, jsonb, text);

create or replace function admin_decide_channel(
  p_channel_id text,
  p_channel_title text,
  p_channel_photo text,
  p_channel_bio text,
  p_videos jsonb,
  p_decision text,
  p_category text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_count int := 0;
  v_cascaded_count int := 0;
begin
  if not is_admin() then
    raise exception 'not authorized';
  end if;
  if p_decision not in ('approved', 'rejected') then
    raise exception 'invalid decision: %', p_decision;
  end if;

  insert into yt_channels (channel_id, channel_title, channel_photo, channel_bio, curation_status, category)
  values (p_channel_id, p_channel_title, p_channel_photo, p_channel_bio, p_decision, p_category)
  on conflict (channel_id) do update
    set channel_title = excluded.channel_title,
        channel_photo = excluded.channel_photo,
        channel_bio = excluded.channel_bio,
        curation_status = excluded.curation_status,
        category = coalesce(excluded.category, yt_channels.category);

  -- Also backfills category on these rows — they're existing 'pending' videos that
  -- predate this channel's category being set (e.g. inserted by the local sync
  -- script, which never writes category at all), not just newly-fetched ones.
  -- Without this, a channel's older pending videos would get approved with
  -- category left NULL and never surface under that category in the sidebar.
  update yt_videos
    set filter_status = p_decision,
        category = coalesce(p_category, category)
    where channel_id = p_channel_id and filter_status = 'pending';
  get diagnostics v_cascaded_count = row_count;

  if p_decision = 'approved' then
    insert into yt_videos (
      video_id, channel_id, channel_title, channel_photo,
      title, description, thumbnail, published_at, filter_status, category
    )
    select
      v->>'video_id',
      p_channel_id,
      p_channel_title,
      p_channel_photo,
      v->>'title',
      v->>'description',
      v->>'thumbnail',
      (v->>'published_at')::timestamptz,
      'approved',
      p_category
    from jsonb_array_elements(coalesce(p_videos, '[]'::jsonb)) as v
    where v->>'video_id' is not null
      and not exists (select 1 from yt_videos ev where ev.video_id = v->>'video_id');
    get diagnostics v_new_count = row_count;
  end if;

  return jsonb_build_object('new_videos_inserted', v_new_count, 'existing_videos_cascaded', v_cascaded_count);
end;
$$;

revoke all on function admin_decide_channel(text, text, text, text, jsonb, text, text) from public;
grant execute on function admin_decide_channel(text, text, text, text, jsonb, text, text) to authenticated;
