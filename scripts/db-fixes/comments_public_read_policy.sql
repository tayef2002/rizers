-- Run in Supabase SQL editor.
-- comments currently only lets each user read their OWN rows via RLS — confirmed live:
-- inserted a comment as one account, then querying with .neq('user_id', thatAccount) returned
-- zero rows even filtered to the exact same post_id, though the comment definitely existed
-- (readable when filtered back to its own author). That breaks the entire comments feature,
-- since seeing everyone's comments on a post is the whole point (same as posts/post_reactions,
-- which are already publicly readable).
--
-- RLS policies are OR'd together — adding this permissive read policy makes every row visible
-- regardless of whatever restrictive policy already exists, without needing to know its name
-- or replace it. Doesn't touch insert/update/delete policies.
drop policy if exists "comments_select_all" on comments;
create policy "comments_select_all" on comments for select using (true);
