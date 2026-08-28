-- Run in Supabase SQL editor.
-- Adds a stored YouTube @handle per channel, so Creator Profile pages get a real
-- shareable URL (rizers.pages.dev/creator/@handle) instead of only being reachable
-- from inside the app via an internal channel_id. Mirrors the existing
-- profiles.username -> /@username pattern exactly (lowercase-stored, exact-match
-- lookup, no leading @ in the stored value).

alter table yt_channels add column if not exists channel_handle text;

-- Case-insensitive uniqueness (two channels can't claim the same handle) — partial
-- index so channels with no handle yet (legacy/never-refreshed) don't collide on NULL.
create unique index if not exists yt_channels_handle_idx on yt_channels (lower(channel_handle)) where channel_handle is not null;

-- Adding a parameter changes the function's signature, so `create or replace` would
-- silently create a SECOND overload alongside the existing 7-argument version instead
-- of replacing it — explicitly dropping the old signature first avoids two ambiguous
-- admin_decide_channel functions existing at once (which breaks PostgREST's RPC
-- resolution). See rizplay_sidebar_features.sql for the same trap hit earlier.
drop function if exists admin_decide_channel(text, text, text, text, jsonb, text, text);

create or replace function admin_decide_channel(
  p_channel_id text,
  p_channel_title text,
  p_channel_photo text,
  p_channel_bio text,
  p_videos jsonb,
  p_decision text,
  p_category text default null,
  p_channel_handle text default null
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

  insert into yt_channels (channel_id, channel_title, channel_photo, channel_bio, curation_status, category, channel_handle)
  values (p_channel_id, p_channel_title, p_channel_photo, p_channel_bio, p_decision, p_category, p_channel_handle)
  on conflict (channel_id) do update
    set channel_title = excluded.channel_title,
        channel_photo = excluded.channel_photo,
        channel_bio = excluded.channel_bio,
        curation_status = excluded.curation_status,
        category = coalesce(excluded.category, yt_channels.category),
        channel_handle = coalesce(excluded.channel_handle, yt_channels.channel_handle);

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

revoke all on function admin_decide_channel(text, text, text, text, jsonb, text, text, text) from public;
grant execute on function admin_decide_channel(text, text, text, text, jsonb, text, text, text) to authenticated;
