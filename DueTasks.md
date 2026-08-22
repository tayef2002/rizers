# Rizers — Due Tasks & App Status

> Last updated: 2026-08-11
> Full codebase audit done. Read this file at the start of every session to avoid re-doing research.

---

## Architecture Overview
- Single HTML app: `index.html` loads page fragments from `pages/*.html`
- All JS logic: `js/app.js` (~32,800 lines)
- Backend: Supabase (auth, realtime, storage)
- Two modes: **Kids mode** (Supabase-backed) | **Adult mode** (mostly localStorage only)

---

## ✅ COMPLETE — No work needed

| Feature | File | Notes |
|---|---|---|
| Community Feed | pages/community.html | Posts, reactions, comments, voice posts — real Supabase |
| Knokz Messaging | pages/knokz.html | DM, voice, image, realtime, WhatsApp ticks, read receipts, groups |
| Profile | pages/profile.html | Cover, avatar upload, rizer system, visitor mode — real Supabase |
| Notifications | js/app.js | Panel, badge, realtime subscription, avatar fallback — done |
| Splash Screen | index.html | Dark bg, grid, icons, rotating taglines, 2s timer — done |
| Dashboard (Kids) | pages/dashboard.html | Real Supabase data |
| Namaz (Kids) | pages/namaz.html | Real Supabase — namaz_logs table |
| Habits (Kids) | pages/habits.html | Real Supabase — habits + habit_logs tables |
| Quran (Kids) | pages/quran.html | Real Supabase — quran_progress table |
| Sleep (Kids) | pages/sleep.html | Real Supabase — sleep_logs table |
| Study (Kids) | pages/study.html | Real Supabase — study_sessions table |
| Reading (Kids) | pages/reading.html | Real Supabase — reading_logs table |
| Search | js/app.js | Navigation search across all 30 pages — works |
| Settings (profile edit) | pages/settings.html | Name, username → real Supabase profiles table |
| URL routing | js/app.js | Every top-level page has `/pagename`, every profile has `/@username` — pushState/popstate, browser Back/Forward works. No deep-linking into sub-states (specific chat/challenge/video) yet. |
| Challenges | pages/challenges.html | Create/join/post, membership enforced server-side (BEFORE INSERT trigger), posts surface in both challenge page and Rise Feed |
| Hadi (AI Partner) | js/app.js | In-Knokz AI assistant — Groq chat models w/ fallback chain, Gemini fallback, action execution (add habit/todo/goal, log namaz, etc.), voice transcription. Calls proxied through `supabase/functions/groq-proxy` — see Security note below. |

---

## ⚠️ PARTIAL — Has UI but needs work

### Adult Productivity (localStorage only — data lost on device change)
These all have FULL UI and JS logic but zero Supabase backing.
Highest priority to fix if adult users matter.

| Feature | File | What's missing |
|---|---|---|
| Goals | pages/goals.html | ✅ Migrated to Supabase (`adult_goals` table) |
| Todo | pages/todo.html | ✅ Migrated to Supabase (`todo_tasks` + `todo_projects` tables) |
| Journal | pages/journal.html | ✅ Migrated to Supabase (`journal_entries` table) |
| Deep Work | pages/deepwork.html | ✅ Migrated to Supabase (`deepwork_sessions` + `deepwork_settings` tables) |
| Book Notes | pages/booknotes.html | ✅ Uses Smart Notes (`smart_notes` table) — already migrated |
| Weekly Review | pages/weeklyreview.html | ✅ Migrated to Supabase (`weekly_reviews` table) |
| Fasting | pages/fasting.html | ✅ Migrated to Supabase (`fasting_logs` + `fasting_settings` tables) |
| Finance (Adult) | pages/finance.html | ✅ Migrated to Supabase (`finance_transactions` + `finance_settings` tables) |
| Namaz (Adult) | pages/namaz.html | ✅ Migrated to Supabase (`adult_namaz_logs` table) |
| Quran (Adult) | pages/quran.html | ✅ Migrated to Supabase (`adult_quran_data` table) |
| Habits (Adult) | pages/habits.html | ✅ Migrated to Supabase (`adult_habits` table) |
| Sleep (Adult) | pages/sleep.html | ✅ Migrated to Supabase (`adult_sleep_logs` + `adult_sleep_settings` tables) |
| Study (Adult) | pages/study.html | ✅ Migrated to Supabase (`adult_study_data` table) |
| Reading (Adult) | pages/reading.html | ✅ Migrated to Supabase (`adult_reading_data` table) |
| Screen Time | pages/screentime.html | localStorage only, manual input. Adult functions are EMPTY stubs |

### Social / Monetization (partial)

| Feature | File | What's missing |
|---|---|---|
| Rewards | pages/rewards.html | Coin balance from localStorage with hardcoded fallback 1240. No real server coin ledger. Badges hardcoded. Challenges static. |
| Referral | pages/referral.html | All stats from localStorage (always 0 for new users). Leaderboard is fake hardcoded data. Referral code is client-side only — no server tracking. |
| Stories (Islamic library) | pages/stories.html | Only 5 hardcoded Bengali stories in `stData` array. Community stories (posts) are real Supabase. |
| Settings (subscription) | pages/settings.html | Subscription status from localStorage. Payment (bKash) is `alert('coming soon!')`. Password change is `alert('coming soon!')`. Data export is `alert('coming soon!')`. |
| Dashboard (Adult) | pages/dashboard.html | ✅ Goals + Todo live from Supabase; Sleep from localStorage |
| RizPlay | pages/rizplay.html | No longer empty — desktop grid + watch view, creator demo profiles, YouTube-sync backend (video_reactions, cover text columns), sidebar/feed cross-promo widgets in Community. Still has uncommitted WIP as of 2026-07-26; verify creator profiles are real vs demo data before calling this complete. |

---

## ❌ EMPTY — Placeholder only, no functionality

| Feature | File | Current state |
|---|---|---|
| Finance (Kids) | pages/finance.html | Kids section shows "Finance tracker coming soon" |

**2026-08-11:** Islamic Finance, Dawah, Family, Marriage, Parenting, and Tafseer were removed entirely (page fragments, nav entries, dashboard Quick Access tiles, all lookup-table references) — they were unbuilt "coming soon" stubs never in original scope, and the user chose to delete rather than ship dead-end pages. Can be re-added individually later if actually built out.

---

## 🐛 Known Bugs / Issues Fixed This Session
- ✅ Voice waveform persistence (base64 encoded in message content)
- ✅ Voice progress bar stuck at 0 (WebM `duration = Infinity` bug — fixed with cache)
- ✅ WhatsApp-style SVG tick marks (single → double → blue)
- ✅ Blue read receipts via Supabase realtime
- ✅ Notification avatar onerror fallback (broken image → initials)
- ✅ Notification realtime subscription (badge auto-updates)
- ✅ rise_request notification hidden after accept
- ✅ Splash screen full redesign (grid, icons, stars, 2s timer, rotating taglines)

---

## 📋 Suggested Priority Order for Next Work

### Tier 1 — Launch blockers
1. **Settings subscription/payment** — bKash integration or real payment flow
2. **Rewards real coin system** — Server-side coin ledger via Supabase
3. **Screen Time (adult)** — still localStorage-only, adult functions are empty stubs

### Tier 2 — Retention features
4. **Referral real tracking** — Server-side referral code + join tracking
5. **RizPlay polish** — confirm creator profiles are real (not demo) data, finish commit of current WIP

### Tier 3 — Content & engagement
6. **Islamic Stories library** — More stories from Supabase, not hardcoded

---

## 💡 Future Idea — MCP Integration (Rizers ↔ Claude)

**2026-07-26:** Discussed letting individual Rizers users connect their own Rizers profile to Claude (Claude.ai / Desktop / Code → Connectors), the same way users connect Notion, Google Calendar, or Canva today.

**Mechanism (confirmed feasible):**
- Build a **remote MCP server** — a new hosted endpoint (natural fit: another `supabase/functions/*` edge function alongside `groq-proxy`) exposing Rizers actions as MCP tools: `get_habits`, `add_todo`, `log_namaz`, `get_dashboard_stats`, `create_post`, etc. — thin wrappers around existing Supabase queries.
- Each user clicks "Connect" inside Claude's Connectors UI, goes through an OAuth login against Rizers, and Claude can then read/act on *that specific user's* data going forward, scoped by their own Supabase RLS.

**Main tradeoff / hard part:** not the tools themselves (straightforward Supabase wrappers) — it's building the **OAuth authorization flow** (`/authorize` + `/token`, PKCE) that Claude's connector UI expects. Supabase Auth doesn't expose this out of the box, so it needs a thin OAuth wrapper on top that maps an issued token back to a Supabase user session for the edge function to use per tool call.

**Status:** idea only, not started. Next step when picked up: decide which tools to expose first, design the OAuth wrapper, and where in the repo it lives (likely `supabase/functions/mcp/`).

---

## 🔒 Security

- **2026-07-26:** Two Groq API keys were found hardcoded in `js/app.js` (shipped to every browser — anyone could view-source and steal them). Fixed by routing all Groq calls (Hadi AI Partner + Rizers AI Core voice intent) through a new server-side proxy, `supabase/functions/groq-proxy` (requires a valid Supabase user JWT; the actual Groq key lives only in the function's `GROQ_API_KEY` env secret). Both leaked keys must be rotated in the Groq console — if you're reading this and that hasn't happened yet, do it before anything else.
- Live Supabase project ref used by the app's `_sb` client is **`zsmyscntuunrmzekdxjo`**, not `xwdmhwaxzwowlezqruaj` (that string only appears as a legacy domain suffix in synthetic phone-login emails — don't confuse the two).
- **2026-08-01:** `comments` table's RLS only allows each user to SELECT their own rows — confirmed live (insert as user A, query with `.neq('user_id', A)`, get zero rows even filtered to the same post). This means **nobody can currently see anyone else's comments** on any post. Fix is ready at `scripts/db-fixes/comments_public_read_policy.sql` (adds a permissive `for select using (true)` policy — RLS policies OR together, so this doesn't require knowing/removing whatever restrictive policy already exists) — just needs to actually be run against Supabase, same DB-access blocker as the `video_reactions`/`video_comments` migration above.

---

## 🐛 Resolved (was misdiagnosed as fading, actually a layout bug)

- **2026-08-01 — Desktop post-detail modal squeezed comments to an unreadable sliver, and the header/× button were unreachable, on shorter browser windows.** First reported as "the modal fades a few seconds after opening" — that framing was wrong (user corrected it directly after seeing a screenshot: the content was still there, just barely visible through a gap, and scrolling didn't work). Real cause: `#cm-pm-post-section` (holds the post image/caption) had `flex-shrink:0` and no height cap, so a tall image could grow to its full natural height (confirmed 768px for one real post) — it never shrank, so it squeezed `#cm-pm-cmt-section` (`flex:1`) down to almost nothing on a shorter viewport, and only cmt-section had `overflow-y:auto`, so there was no way to scroll back up to the now-cramped header/close button either. First pass capped post-section to `max-height:38vh` with its own scroll — fixed the comment squeeze, but then cramming avatar+name+caption+image+stats+actions into that same small box left almost none of that budget for the image, so seeing the full photo via scroll still felt broken (caught immediately from a follow-up screenshot). Real fix: wrapped post-section + cmt-section in a shared `#cm-pm-body` that owns one `flex:1/overflow-y:auto` scroll region — image, caption, and comments now scroll together as one continuous area below the fixed header, same as a normal feed post. Verified live at 900×650: the actual post photo (not the 40px avatar image the first querySelector check accidentally matched) renders at its full natural height, with everything scrolling correctly. The earlier "opacity watchdog" fix (still in `cmOpenPostModal()`) was based on the original wrong diagnosis — harmless to leave, but this layout fix is the one that actually mattered.
- **Related but distinct:** "2 comments not shown" on the same post is *not* part of this rendering bug — confirmed separately as the RLS issue documented under Security above (comments from other users are invisible query-wide, not just in this modal).

---

## Supabase Tables in Use
`profiles`, `notifications`, `posts`, `comments`, `post_reactions`, `rizer_requests`, `rizerships`, `knokz_messages`, `knokz_groups`, `kids`, `habits`, `habit_logs`, `namaz_logs`, `quran_progress`, `sleep_logs`, `study_sessions`, `reading_logs`, `positions`

## Supabase Storage Buckets
`avatars`, `knokz-images`, `knokz-audio`

## localStorage Keys (adult mode)
`rz_adult_namaz_v1`, `rz_adult_quran_v2`, `rz_adult_habits_v2`, `rz_adult_sleep_v2`, `rz_td_data`, `rz_jn_data`, `rz_dw_data`, `rz_read_*`, `rz_fs_meta`, `rz_fs_logs`, `_fn_data`, `WR_KEY`, `_rzc_balance`, `ref_count`, `ref_joined`, `sub_status`, `sub_plan`
