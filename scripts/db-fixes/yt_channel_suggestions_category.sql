-- Run in Supabase SQL editor.
-- Adds a category column to yt_channel_suggestions so the admin panel's
-- Suggestions tab can search (and tag results) one content category at a
-- time instead of one big mixed run.
alter table yt_channel_suggestions add column if not exists category text;
