-- Run in Supabase SQL editor.
-- Gives the admin panel a real approve/reject workflow for RizPlay videos,
-- replacing the "hand-edit filter_status in the table editor" step.
--
-- yt_videos/yt_channels predate this repo's tracked migrations (created
-- directly in the Supabase dashboard) — confirmed live before writing this:
-- RLS is enabled on both, and the only existing policy on yt_videos is a
-- clean, properly-scoped public SELECT ("public can read approved videos",
-- qual: filter_status = 'approved'). No wide-open allow_all-style policy
-- this time, unlike the posts/profiles/comments/post_reactions incidents —
-- just missing admin coverage, which this adds.

-- Admin needs to see pending/rejected rows too, not just approved ones —
-- the existing public policy only covers filter_status='approved'.
drop policy if exists yt_videos_admin_select on yt_videos;
create policy yt_videos_admin_select on yt_videos
  for select using (is_admin());

drop policy if exists yt_videos_admin_update on yt_videos;
create policy yt_videos_admin_update on yt_videos
  for update using (is_admin()) with check (is_admin());

drop policy if exists yt_videos_admin_delete on yt_videos;
create policy yt_videos_admin_delete on yt_videos
  for delete using (is_admin());
