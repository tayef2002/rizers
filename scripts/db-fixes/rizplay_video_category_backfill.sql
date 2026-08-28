-- Run in Supabase SQL editor.
-- One-time (re-runnable) admin-triggered backfill that derives each APPROVED
-- video's OWN category from its title+description text via keyword matching —
-- strictly more granular than admin_decide_channel's blanket channel-level
-- category stamp (see rizplay_sidebar_features.sql / yt_channels_handle.sql,
-- which only ever set category at approval time, uniformly per channel).
-- No AI/LLM: pure substring matching against a priority-ordered keyword list
-- per category — most-specific/narrowest category checked first, so e.g. an
-- occasion-specific "Eid Dua" title lands under Ramadan & Islamic Occasions
-- rather than the much more generic Dua & Dhikr bucket, and a
-- self-improvement video only falls into the broad "Productivity &
-- Self-Improvement" catch-all if it didn't already match the narrower
-- Study/Time-Management buckets first.

-- Internal classifier — deliberately NOT granted to authenticated/anon below;
-- only ever called from admin_backfill_video_categories(). Pure function of
-- its two text inputs, no table access, so immutable is correct.
create or replace function _rz_classify_video_category(p_title text, p_description text)
returns text
language sql
immutable
as $$
  with m as (
    select lower(coalesce(p_title, '') || ' ' || coalesce(p_description, '')) as t
  )
  select
    case
      -- Quran Tafsir before Quran Recitation: trigger words are fully disjoint
      -- (তাফসীর/tafsir vs তেলাওয়াত/recitation) — order here is defensive only.
      when t like any (array['%তাফসীর%','%তাফসির%','%tafsir%','%tafseer%','%तफ़सीर%','%तफसीर%']::text[]) then 'Quran Tafsir'
      when t like any (array['%তেলাওয়াত%','%তিলাওয়াত%','%tilawat%','%tilawah%','%recitation%','%तिलावत%']::text[]) then 'Quran Recitation'
      when t like any (array['%হাদিস%','%হাদীস%','%hadith%','%hadeeth%','%हदीस%']::text[]) then 'Hadith'
      when t like any (array['%সীরাত%','%সিরাত%','%নবীজির জীবনী%','%নবীর জীবনী%','%seerah%','%sirah%','%prophet biography%','%सीरत%']::text[]) then 'Seerah & Islamic History'
      when t like any (array['%ইসলাম গ্রহণ%','%dawah%','%revert to islam%','%new muslim%','%नया मुस्लिम%']::text[]) then 'Dawah & New Muslims'
      -- Occasion names before Dua & Dhikr — "Eid dua"/"Ramadan dua" is about the
      -- occasion; 'dua' alone is far too generic (dua for exams, for parents...)
      -- to let it steal occasion-named titles.
      when t like any (array['%রমজান%','%রমাদান%','%ঈদ%','%ramadan%','%ramzan%','%eid%','%qurbani%','%ashura%','%रमज़ान%','%ईद%']::text[]) then 'Ramadan & Islamic Occasions'
      when t like any (array['%ওয়াজ%','%মাহফিল%','%বয়ান%','%waz mahfil%','%waz%','%mahfil%','%bayan%','%islamic lecture%','%बयान%']::text[]) then 'Islamic Lectures'
      when t like any (array['%জিকির%','%যিকির%','%দোয়া%','%dhikr%','%zikr%','%dua%','%ज़िक्र%','%दुआ%']::text[]) then 'Dua & Dhikr'
      when t like any (array['%মুসলিম পরিবার%','%ইসলামিক পরিবার%','%islamic parenting%','%muslim family%','%islamic family%']::text[]) then 'Islamic Parenting & Family'
      when t like any (array['%হালাল ইনকাম%','%হালাল ব্যবসা%','%islamic finance%','%halal income%','%halal business%','%halal investment%','%interest free%','%riba free%']::text[]) then 'Islamic Finance & Halal Income'
      -- Narrowest of the three self-help buckets first (student/exam-specific).
      when t like any (array['%স্টাডি মোটিভেশন%','%পড়াশোনা%','%study motivation%','%student motivation%','%exam motivation%']::text[]) then 'Study & Student Motivation'
      when t like any (array['%টাইম ম্যানেজমেন্ট%','%time management%','%discipline motivation%','%self discipline%']::text[]) then 'Time Management & Discipline'
      -- Broadest self-help umbrella — catches what Study/Time-Management didn't.
      when t like any (array['%প্রোডাক্টিভিটি%','%productivity%','%self improvement%','%self-improvement%']::text[]) then 'Productivity & Self-Improvement'
      -- Broadest catch-all overall — checked last on purpose (see file header).
      when t like any (array['%নসিহত%','%নসীহত%','%muslim motivation%','%islamic reminder%','%islamic motivation%','%नसीहत%']::text[]) then 'Reminders & Motivation'
      else null
    end
  from m;
$$;

revoke all on function _rz_classify_video_category(text, text) from public;

create or replace function admin_backfill_video_categories(
  p_dry_run boolean default true,
  p_overwrite boolean default false
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_by_category jsonb;
  v_total bigint;
begin
  if not is_admin() then
    raise exception 'not authorized';
  end if;

  if p_dry_run then
    select coalesce(jsonb_object_agg(derived_category, cnt), '{}'::jsonb),
           coalesce(sum(cnt), 0)
      into v_by_category, v_total
    from (
      select derived_category, count(*) as cnt
      from (
        select _rz_classify_video_category(title, description) as derived_category
        from yt_videos
        where filter_status = 'approved'
          and (category is null or p_overwrite)
      ) s
      where derived_category is not null
      group by derived_category
    ) grouped;

    return jsonb_build_object('dry_run', true, 'count', v_total, 'by_category', v_by_category);
  end if;

  with classified as (
    select video_id, _rz_classify_video_category(title, description) as derived_category
    from yt_videos
    where filter_status = 'approved'
      and (category is null or p_overwrite)
  ),
  updated as (
    update yt_videos v
    set category = c.derived_category
    from classified c
    where v.video_id = c.video_id
      and c.derived_category is not null
    returning c.derived_category
  )
  select coalesce(jsonb_object_agg(derived_category, cnt), '{}'::jsonb),
         coalesce(sum(cnt), 0)
    into v_by_category, v_total
  from (
    select derived_category, count(*) as cnt
    from updated
    group by derived_category
  ) grouped;

  return jsonb_build_object('dry_run', false, 'count', v_total, 'by_category', v_by_category);
end;
$$;

revoke all on function admin_backfill_video_categories(boolean, boolean) from public;
grant execute on function admin_backfill_video_categories(boolean, boolean) to authenticated;
