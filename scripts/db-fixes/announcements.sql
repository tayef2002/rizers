-- Run in Supabase SQL editor.
-- Site-wide announcement banner, managed from the admin panel. Deliberately
-- NOT wired into the existing per-user `notifications` table (bell/sheet)
-- — that table's real column shape has a confirmed drift (some call sites
-- use msg/read, others body/is_read) that hasn't been resolved, and
-- fanning out one row per user for a broadcast doesn't fit its per-user
-- design anyway. This is a clean, standalone table instead: a banner
-- rendered from index.html's shell (so it shows on every page with no
-- per-page wiring), dismissed client-side per announcement id.

create table if not exists announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  message text not null,
  link_url text,
  link_text text,
  is_active boolean not null default true,
  starts_at timestamptz,
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id)
);

alter table announcements enable row level security;

-- Regular users only ever see the currently-active, currently-in-range
-- rows — never inactive, future-scheduled, or expired ones.
drop policy if exists announcements_select_current on announcements;
create policy announcements_select_current on announcements
  for select using (
    is_active
    and (starts_at is null or starts_at <= now())
    and (ends_at is null or ends_at >= now())
  );

drop policy if exists announcements_admin_all on announcements;
create policy announcements_admin_all on announcements
  for all using (is_admin()) with check (is_admin());
