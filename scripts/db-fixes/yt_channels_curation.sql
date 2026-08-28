-- Run in Supabase SQL editor.
-- Adds channel-level curation to RizPlay: approving a CHANNEL cascades to all of
-- its videos (current + future), while an admin's individual per-video
-- approve/reject decision is never overwritten by a channel-level action.
--
-- yt_channels predates this repo's tracked migrations (created directly in the
-- Supabase dashboard) — RLS is enabled, existing public SELECT policy is
-- unrelated (creator-profile self-consent via `status`), no admin coverage yet.

alter table yt_channels add column if not exists curation_status text not null default 'pending';

alter table yt_channels drop constraint if exists yt_channels_curation_status_check;
alter table yt_channels add constraint yt_channels_curation_status_check
  check (curation_status in ('pending', 'approved', 'rejected'));

-- Backfill: any channel that already has approved videos today was implicitly
-- approved by the per-video-only workflow (Phase 5) — mark it approved so
-- existing live content doesn't regress into a "pending channel" state.
update yt_channels c set curation_status = 'approved'
where exists (
  select 1 from yt_videos v where v.channel_id = c.channel_id and v.filter_status = 'approved'
);

drop policy if exists yt_channels_admin_select on yt_channels;
create policy yt_channels_admin_select on yt_channels
  for select using (is_admin());

drop policy if exists yt_channels_admin_update on yt_channels;
create policy yt_channels_admin_update on yt_channels
  for update using (is_admin()) with check (is_admin());

drop policy if exists yt_channels_admin_delete on yt_channels;
create policy yt_channels_admin_delete on yt_channels
  for delete using (is_admin());

-- Single entry point for "approve/reject this channel" from the admin panel.
-- Runs as security definer so it can write across yt_channels + yt_videos
-- atomically; the is_admin() check inside is the real gate (RPC calls are NOT
-- covered by table RLS policies on their own — anyone with the anon key could
-- call this function by name if it didn't check admin-ness itself).
--
-- Cascade rule: a channel decision (approve/reject) only ever touches videos
-- still sitting in 'pending'. A video an admin has individually approved or
-- rejected is never flipped back by a channel-level action — this is what
-- lets "channel is otherwise perfect, but this one video isn't" keep working
-- even after the channel itself is approved.
create or replace function admin_decide_channel(
  p_channel_id text,
  p_channel_title text,
  p_channel_photo text,
  p_channel_bio text,
  p_videos jsonb,
  p_decision text
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

  insert into yt_channels (channel_id, channel_title, channel_photo, channel_bio, curation_status)
  values (p_channel_id, p_channel_title, p_channel_photo, p_channel_bio, p_decision)
  on conflict (channel_id) do update
    set channel_title = excluded.channel_title,
        channel_photo = excluded.channel_photo,
        channel_bio = excluded.channel_bio,
        curation_status = excluded.curation_status;

  update yt_videos
    set filter_status = p_decision
    where channel_id = p_channel_id and filter_status = 'pending';
  get diagnostics v_cascaded_count = row_count;

  -- A rejected channel's videos are never stored — nothing worth keeping, and
  -- re-fetching later (if reconsidered) picks them straight back up.
  if p_decision = 'approved' then
    insert into yt_videos (
      video_id, channel_id, channel_title, channel_photo,
      title, description, thumbnail, published_at, filter_status
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
      'approved'
    from jsonb_array_elements(coalesce(p_videos, '[]'::jsonb)) as v
    where v->>'video_id' is not null
      and not exists (select 1 from yt_videos ev where ev.video_id = v->>'video_id');
    get diagnostics v_new_count = row_count;
  end if;

  return jsonb_build_object('new_videos_inserted', v_new_count, 'existing_videos_cascaded', v_cascaded_count);
end;
$$;

revoke all on function admin_decide_channel(text, text, text, text, jsonb, text) from public;
grant execute on function admin_decide_channel(text, text, text, text, jsonb, text) to authenticated;
