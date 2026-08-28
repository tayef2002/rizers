-- Run in Supabase SQL editor.
-- Moves the Reys economy's hardcoded numbers into two admin-editable
-- tables, so the daily claim amount, challenge join fee, progress-post
-- reward, custom-purchase rate, and the 4 bKash purchase tiers can all be
-- changed from the admin panel without a code deploy.
--
-- Also restores claim_daily_reys() to the daily_free_reys-expiring model —
-- it had regressed to the older permanent-reys_balance model (confirmed
-- live during Phase 2 testing), which js/app.js's daily-claim UI was never
-- updated to match. See project memory for the full history; this bundles
-- that fix in since the function needs rewriting here anyway.

/* ══════════════════════════════════════════════════════════════
   Config tables
══════════════════════════════════════════════════════════════ */

create table if not exists reys_config (
  key text primary key,
  value numeric not null,
  description text,
  updated_at timestamptz not null default now()
);

insert into reys_config (key, value, description) values
  ('daily_claim_amount', 300, 'Free Reys granted per daily claim (expires at midnight if unused)'),
  ('challenge_join_fee', 100, 'Reys cost to join a challenge (the creator is exempt)'),
  ('progress_post_reward', 15, 'Reys awarded for the first progress post in a challenge each day'),
  ('custom_purchase_rate', 33.333333, 'Reys granted per 1 Taka for custom (non-tier) bKash purchases')
on conflict (key) do nothing;

alter table reys_config enable row level security;
drop policy if exists reys_config_select_all on reys_config;
create policy reys_config_select_all on reys_config for select using (true);
drop policy if exists reys_config_admin_update on reys_config;
create policy reys_config_admin_update on reys_config for update using (is_admin()) with check (is_admin());

create table if not exists reys_purchase_tiers (
  id uuid primary key default gen_random_uuid(),
  amount_taka numeric not null,
  reys_amount integer not null,
  eyebrow_text text,
  badge_text text,
  is_featured boolean not null default false,
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into reys_purchase_tiers (amount_taka, reys_amount, eyebrow_text, badge_text, is_featured, sort_order)
select * from (values
  (30::numeric,  1000, 'শুরু',        null,          false, 1),
  (50::numeric,  1900, 'বেসিক',       '+১৫%',        false, 2),
  (100::numeric, 4000, '+২০% bonus',  'জনপ্রিয়',     true,  3),
  (300::numeric, 13000,'সেরা মূল্য',  '+৩০%',        false, 4)
) as seed(amount_taka, reys_amount, eyebrow_text, badge_text, is_featured, sort_order)
where not exists (select 1 from reys_purchase_tiers);

alter table reys_purchase_tiers enable row level security;
drop policy if exists reys_purchase_tiers_select_active on reys_purchase_tiers;
create policy reys_purchase_tiers_select_active on reys_purchase_tiers
  for select using (active or is_admin());
drop policy if exists reys_purchase_tiers_admin_all on reys_purchase_tiers;
create policy reys_purchase_tiers_admin_all on reys_purchase_tiers
  for all using (is_admin()) with check (is_admin());

/* ══════════════════════════════════════════════════════════════
   Wire the config into the functions that used to hardcode these numbers
══════════════════════════════════════════════════════════════ */

-- Restores the daily_free_reys-expiring model (see header comment) and
-- reads the amount from config instead of a literal 300.
create or replace function claim_daily_reys()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_last date;
  v_amount integer;
  v_perm_balance integer;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;
  if is_banned() then
    raise exception 'Account suspended';
  end if;
  select last_reys_claim_date, reys_balance into v_last, v_perm_balance from profiles where id = v_uid for update;
  if v_last = current_date then
    raise exception 'Already claimed today';
  end if;
  select value::integer into v_amount from reys_config where key = 'daily_claim_amount';
  v_amount := coalesce(v_amount, 300);
  update profiles set daily_free_reys = v_amount, last_reys_claim_date = current_date
    where id = v_uid;
  -- daily_free_reys is a separate column from reys_balance (permanent), so
  -- balance_after here tracks reys_balance same as every other ledger row —
  -- it's unaffected by this claim, not a display bug (Settings > Reys
  -- History only ever shows amount/description/icon, never balance_after).
  insert into reys_transactions(user_id, amount, balance_after, type, description)
    values (v_uid, v_amount, coalesce(v_perm_balance,0), 'daily_claim', 'দৈনিক ফ্রি Reys');
  return v_amount;
end;
$$;

grant execute on function claim_daily_reys() to authenticated;

create or replace function chl_join_challenge(p_challenge_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_creator_id uuid;
  v_title text;
  v_balance integer;
  v_cost integer;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;
  if is_banned() then raise exception 'Account suspended'; end if;

  select value::integer into v_cost from reys_config where key = 'challenge_join_fee';
  v_cost := coalesce(v_cost, 100);

  select creator_id, title into v_creator_id, v_title from challenges where id = p_challenge_id;
  if v_creator_id is null then raise exception 'Challenge not found'; end if;

  if exists (select 1 from challenge_participants where challenge_id=p_challenge_id and user_id=v_uid) then
    raise exception 'Already joined';
  end if;

  if v_creator_id = v_uid then
    insert into challenge_participants(challenge_id, user_id) values (p_challenge_id, v_uid);
    select reys_balance into v_balance from profiles where id=v_uid;
    return coalesce(v_balance,0);
  end if;

  select reys_balance into v_balance from profiles where id=v_uid for update;
  if coalesce(v_balance,0) < v_cost then
    raise exception 'Not enough Reys';
  end if;

  insert into challenge_participants(challenge_id, user_id) values (p_challenge_id, v_uid);
  update profiles set reys_balance = reys_balance - v_cost where id=v_uid returning reys_balance into v_balance;
  insert into reys_transactions(user_id, amount, balance_after, type, description)
    values (v_uid, -v_cost, v_balance, 'challenge_join', coalesce(v_title, 'Challenge'));
  return v_balance;
end;
$$;

grant execute on function chl_join_challenge(uuid) to authenticated;

create or replace function chl_enforce_post_membership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_already_rewarded_today boolean;
  v_reward integer;
begin
  if new.challenge_id is not null then
    if not exists (
      select 1 from challenge_participants
      where challenge_id = new.challenge_id and user_id = new.user_id
    ) then
      raise exception 'Must be a member of this challenge to post in it';
    end if;

    if new.category = 'progress' then
      select exists(
        select 1 from posts
        where challenge_id = new.challenge_id
          and user_id = new.user_id
          and category = 'progress'
          and created_at::date = current_date
      ) into v_already_rewarded_today;
      if not v_already_rewarded_today then
        select value::integer into v_reward from reys_config where key = 'progress_post_reward';
        update profiles set reys_balance = coalesce(reys_balance,0) + coalesce(v_reward, 15) where id = new.user_id;
      end if;
    end if;
  end if;
  return new;
end;
$$;
-- Trigger itself (chl_enforce_post_membership_trg on posts) is unchanged.
