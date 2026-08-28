-- Run in Supabase SQL editor.
-- Powers the Analytics tab in admin.html: overview stat cards + daily
-- signups/revenue/posts for the last N days, plus Reys economy, RizPlay
-- pipeline, Challenges, and user verification/safety breakdowns — all
-- computed server-side in one call so the client isn't stitching together
-- many separate queries.
--
-- Signup dates: profiles.created_at exists but is unpopulated for every
-- current row (confirmed live: 4 total users, 0 with a signup date) — it was
-- added to the table but never actually set on insert. auth.users.created_at
-- is Supabase's own account-creation timestamp and is always populated, so
-- signups_by_day reads from there instead. Wrapped in its own exception
-- handler — if this project's role doesn't have access to auth.users for any
-- reason, the rest of the dashboard still returns instead of the whole RPC
-- failing.
--
-- Every by-day series is zero-filled across ALL p_days consecutive days
-- (via generate_series + left join), not just days that had activity —
-- otherwise a chart with real gaps (e.g. one signup on day 1, the next on
-- day 14) renders those two points as adjacent bars with no visual gap,
-- which misrepresents the actual timeline.
--
-- Reys ledger note: reys_transactions only ever gets a row for 4 event
-- types — 'daily_claim', 'purchase', 'challenge_join', 'admin_adjustment'.
-- Streak Freeze and the daily progress reward change profiles.reys_balance
-- directly with no ledger row, so reys_by_type below is an honest partial
-- picture of ledgered activity, not a complete source/sink accounting —
-- don't extend this comment's claim without also updating those features
-- to write to the ledger.
create or replace function admin_analytics_overview(p_days int default 30)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total_users int;
  v_total_revenue numeric;
  v_pending_revenue numeric;
  v_pending_count int;
  v_total_posts int;
  v_active_users_7d int;
  v_signups_by_day jsonb;
  v_revenue_by_day jsonb;
  v_posts_by_day jsonb;
  v_reys_circulation numeric;
  v_reys_by_type jsonb;
  v_channels_total int;
  v_channels_approved int;
  v_channels_pending int;
  v_channels_rejected int;
  v_videos_total int;
  v_videos_approved int;
  v_videos_pending int;
  v_videos_rejected int;
  v_pending_suggestions int;
  v_challenges_total int;
  v_challenge_participants_total int;
  v_top_challenges jsonb;
  v_verified_users int;
  v_banned_users int;
begin
  if not is_admin() then
    raise exception 'not authorized';
  end if;

  -- p_days drives generate_series for 3 different by-day breakdowns below —
  -- clamp it so a stray/forged call (the client only ever sends 7/30/90, but
  -- this RPC is reachable by any admin session directly) can't force a
  -- multi-year jsonb_agg across all three series at once.
  p_days := greatest(1, least(p_days, 365));

  select count(*) into v_total_users from profiles;

  select coalesce(sum(amount), 0) into v_total_revenue from subscription_payments where status = 'approved';
  select coalesce(sum(amount), 0) into v_pending_revenue from subscription_payments where status = 'pending';
  select count(*) into v_pending_count from subscription_payments where status = 'pending';

  select count(*) into v_total_posts from posts;

  select count(distinct user_id) into v_active_users_7d
  from (
    select user_id from posts where created_at >= now() - interval '7 days'
    union
    select user_id from comments where created_at >= now() - interval '7 days'
  ) recent;

  begin
    select coalesce(jsonb_agg(jsonb_build_object('date', days.d, 'count', coalesce(c.c, 0)) order by days.d), '[]'::jsonb)
    into v_signups_by_day
    from generate_series((current_date - (p_days - 1))::date, current_date::date, interval '1 day') as days(d)
    left join (
      select date_trunc('day', created_at)::date as d, count(*) as c
      from auth.users
      group by 1
    ) c on c.d = days.d;
  exception when others then
    v_signups_by_day := '[]'::jsonb;
  end;

  select coalesce(jsonb_agg(jsonb_build_object('date', days.d, 'amount', coalesce(r.a, 0)) order by days.d), '[]'::jsonb)
  into v_revenue_by_day
  from generate_series((current_date - (p_days - 1))::date, current_date::date, interval '1 day') as days(d)
  left join (
    select date_trunc('day', created_at)::date as d, sum(amount) as a
    from subscription_payments
    where status = 'approved'
    group by 1
  ) r on r.d = days.d;

  select coalesce(jsonb_agg(jsonb_build_object('date', days.d, 'count', coalesce(p.c, 0)) order by days.d), '[]'::jsonb)
  into v_posts_by_day
  from generate_series((current_date - (p_days - 1))::date, current_date::date, interval '1 day') as days(d)
  left join (
    select date_trunc('day', created_at)::date as d, count(*) as c
    from posts
    group by 1
  ) p on p.d = days.d;

  -- Reys economy
  select coalesce(sum(reys_balance), 0) into v_reys_circulation from profiles;

  select coalesce(jsonb_agg(jsonb_build_object('type', t, 'total', total) order by total desc), '[]'::jsonb)
  into v_reys_by_type
  from (
    select type as t, sum(amount) as total
    from reys_transactions
    group by type
  ) rt;

  -- RizPlay pipeline
  select count(*) into v_channels_total from yt_channels;
  select count(*) into v_channels_approved from yt_channels where curation_status = 'approved';
  select count(*) into v_channels_pending from yt_channels where curation_status = 'pending';
  select count(*) into v_channels_rejected from yt_channels where curation_status = 'rejected';

  select count(*) into v_videos_total from yt_videos;
  select count(*) into v_videos_approved from yt_videos where filter_status = 'approved';
  select count(*) into v_videos_pending from yt_videos where filter_status = 'pending';
  select count(*) into v_videos_rejected from yt_videos where filter_status = 'rejected';

  select count(*) into v_pending_suggestions from yt_channel_suggestions where dismissed = false;

  -- Challenges
  select count(*) into v_challenges_total from challenges;
  select count(*) into v_challenge_participants_total from challenge_participants;

  select coalesce(jsonb_agg(jsonb_build_object('title', title, 'participants', participants) order by participants desc), '[]'::jsonb)
  into v_top_challenges
  from (
    select c.title, count(cp.id) as participants
    from challenges c
    left join challenge_participants cp on cp.challenge_id = c.id
    group by c.id, c.title
    order by participants desc
    limit 5
  ) tc;

  -- User verification / safety
  select count(*) into v_verified_users from profiles where is_verified = true;
  select count(*) into v_banned_users from profiles where is_banned = true;

  return jsonb_build_object(
    'total_users', v_total_users,
    'total_revenue', v_total_revenue,
    'pending_revenue', v_pending_revenue,
    'pending_count', v_pending_count,
    'total_posts', v_total_posts,
    'active_users_7d', v_active_users_7d,
    'signups_by_day', v_signups_by_day,
    'revenue_by_day', v_revenue_by_day,
    'posts_by_day', v_posts_by_day,
    'reys_circulation', v_reys_circulation,
    'reys_by_type', v_reys_by_type,
    'channels_total', v_channels_total,
    'channels_approved', v_channels_approved,
    'channels_pending', v_channels_pending,
    'channels_rejected', v_channels_rejected,
    'videos_total', v_videos_total,
    'videos_approved', v_videos_approved,
    'videos_pending', v_videos_pending,
    'videos_rejected', v_videos_rejected,
    'pending_suggestions', v_pending_suggestions,
    'challenges_total', v_challenges_total,
    'challenge_participants_total', v_challenge_participants_total,
    'top_challenges', v_top_challenges,
    'verified_users', v_verified_users,
    'banned_users', v_banned_users
  );
end;
$$;

revoke all on function admin_analytics_overview(int) from public;
grant execute on function admin_analytics_overview(int) to authenticated;
