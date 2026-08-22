-- Run in Supabase SQL editor — adds cover headline/subtext columns for the profile cover
-- text feature (template picker + custom text editor).
alter table profiles add column if not exists cover_headline text;
alter table profiles add column if not exists cover_subtext text;
