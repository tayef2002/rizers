-- Run in Supabase SQL editor.
-- Phase 0 of the admin panel: a real is_admin flag + RLS policies enforced server-side, not
-- just a hidden nav item. Mirrors the existing is_verified_manual_override convention (set by
-- hand, never written by client code) and the sp_activate_on_approval/pf_recompute_completion
-- security-definer pattern already used elsewhere in this schema.

alter table profiles add column if not exists is_admin boolean not null default false;
update profiles set is_admin = true where id = 'b390dcc8-ccde-4188-98da-03c15f5faa50'; -- Tayef's own row

create or replace function is_admin() returns boolean
language sql security definer stable
set search_path = public
as $$ select coalesce((select is_admin from profiles where id = auth.uid()), false); $$;

-- Payments: no UPDATE policy exists for anyone today (owner-only, table-editor-only, by
-- design — see subscription_payments.sql's own comments). Add one gated by is_admin() so the
-- panel can flip status without ever needing the service-role key in the browser.
drop policy if exists subscription_payments_admin_update on subscription_payments;
create policy subscription_payments_admin_update on subscription_payments
  for update using (is_admin()) with check (is_admin());

-- Moderation: the "Report" button has been a 100% client-side no-op (js/app.js cmMenuAction) —
-- this table is what makes it real, plus an admin review queue.
create table if not exists reports (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references posts(id) on delete cascade,
  reporter_id uuid not null references profiles(id),
  reason text,
  status text not null default 'pending', -- pending | reviewed | dismissed
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references profiles(id)
);
alter table reports enable row level security;
drop policy if exists reports_insert_own on reports;
create policy reports_insert_own on reports for insert with check (auth.uid() = reporter_id);
drop policy if exists reports_select_admin on reports;
create policy reports_select_admin on reports for select using (is_admin());
drop policy if exists reports_update_admin on reports;
create policy reports_update_admin on reports for update using (is_admin()) with check (is_admin());

-- Posts: no admin hide/delete path exists today short of the table editor. admin_hidden is a
-- soft-hide (post stays in the DB, just filtered out of every feed query app-wide); DELETE
-- stays available for outright removal.
alter table posts add column if not exists admin_hidden boolean not null default false;
drop policy if exists posts_admin_update on posts;
create policy posts_admin_update on posts for update using (is_admin()) with check (is_admin());
drop policy if exists posts_admin_delete on posts;
create policy posts_admin_delete on posts for delete using (is_admin());
