-- Run in Supabase SQL editor.
-- Lets a profile owner mark individual "About" fields private (visible to themselves only).
-- Stores PF_IE_CFG config keys (js/app.js), e.g. 'city', 'birthday', 'work' — NOT raw DB
-- column names — so one entry ('work') can govern the two columns (work, company) that
-- share a single edit panel. Purely a client-side display filter (see
-- pfHideEmptyVisitorRows in js/app.js) — NOT an RLS-level restriction; any authenticated
-- user can still select('*') the row today (pre-existing gap, unchanged by this migration).
-- Does not affect profile_completion_score / is_verified — pf_recompute_completion()
-- (profile_verification_score.sql) reads raw new.<col> values unconditionally, independent
-- of privacy, and is untouched by this file.

alter table profiles add column if not exists private_fields text[] not null default '{}';
