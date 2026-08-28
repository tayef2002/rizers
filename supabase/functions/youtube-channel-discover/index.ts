// Server-side discovery of candidate YouTube channels for RizPlay curation.
// Admin-triggered only (never automatic) — the admin picks ONE content
// category and one or more languages in the Suggestions tab, this runs just
// that combination's search queries, and drops any candidate already known
// (already in yt_channels, or already suggested before — including
// previously dismissed ones, so a dismiss decision sticks permanently).
// Results land in yt_channel_suggestions for manual review — nothing here
// writes to yt_channels or yt_videos.
import { createClient } from 'jsr:@supabase/supabase-js@2'

const YOUTUBE_API_KEY = Deno.env.get('YOUTUBE_API_KEY')!
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

const VALID_LANGUAGES = ['bn', 'en', 'hi']

// Content categories relevant to Rizers (a Bangladeshi Islamic productivity/
// social app), each with search terms per language (bn=Bangla, en=English,
// hi=Hindi). Deliberately excluded from every category: entertainment/
// movies/gaming (unrelated to the app), instrumental music/nasheed
// (contested category, left to a manual add if ever wanted), and political/
// sectarian content (divisive). There's no AI filtering on results (by
// design — see scripts/db-fixes/yt_channel_suggestions.sql) — this list IS
// the content policy; edit it to add/remove categories, languages, or shift
// what surfaces. IMPORTANT: keep the category names here in sync with
// admin.html's SUGGESTION_CATEGORIES list (used to render the buttons).
const CATEGORIES: Record<string, Record<string, string[]>> = {
  'Quran Recitation': {
    bn: ['কুরআন তেলাওয়াত', 'quran recitation bangla'],
    en: ['quran recitation'],
    hi: ['कुरान तिलावत', 'quran recitation hindi'],
  },
  'Quran Tafsir': {
    bn: ['কুরআন তাফসীর', 'quran tafsir bangla'],
    en: ['quran tafsir'],
    hi: ['कुरान तफ़सीर'],
  },
  'Islamic Lectures': {
    bn: ['ইসলামিক ওয়াজ', 'bangla waz mahfil'],
    en: ['islamic lecture'],
    hi: ['इस्लामिक बयान'],
  },
  'Dua & Dhikr': {
    bn: ['জিকির ও দোয়া', 'dua bangla'],
    en: ['islamic dua'],
    hi: ['दुआ ज़िक्र'],
  },
  'Hadith': {
    bn: ['হাদিস ব্যাখ্যা', 'hadith bangla'],
    en: ['hadith explanation'],
    hi: ['हदीस हिंदी'],
  },
  'Seerah & Islamic History': {
    bn: ['নবীজির জীবনী', 'seerah bangla'],
    en: ['islamic history'],
    hi: ['सीरत हिंदी'],
  },
  'Reminders & Motivation': {
    bn: ['নসিহত', 'islamic reminder bangla'],
    en: ['muslim motivation'],
    hi: ['इस्लामिक नसीहत'],
  },
  'Productivity & Self-Improvement': {
    bn: ['প্রোডাক্টিভিটি', 'self improvement bangla'],
    en: ['islamic productivity', 'self improvement'],
    hi: ['self improvement hindi'],
  },
  'Study & Student Motivation': {
    bn: ['স্টাডি মোটিভেশন', 'study motivation bangla'],
    en: ['student motivation'],
    hi: ['study motivation hindi'],
  },
  'Ramadan & Islamic Occasions': {
    bn: ['রমজান রিমাইন্ডার', 'ramadan bangla'],
    en: ['ramadan reminder'],
    hi: ['रमज़ान हिंदी'],
  },
  'Islamic Parenting & Family': {
    bn: ['মুসলিম পরিবার', 'islamic parenting bangla'],
    en: ['islamic parenting'],
    hi: ['islamic parenting hindi'],
  },
  'Dawah & New Muslims': {
    bn: ['ইসলাম গ্রহণ', 'dawah bangla'],
    en: ['dawah', 'new muslim guide'],
    hi: ['dawah hindi'],
  },
  'Islamic Finance & Halal Income': {
    bn: ['হালাল ইনকাম', 'islamic finance bangla'],
    en: ['islamic finance', 'halal income'],
    hi: ['islamic finance hindi'],
  },
  'Time Management & Discipline': {
    bn: ['টাইম ম্যানেজমেন্ট', 'time management bangla'],
    en: ['time management', 'discipline motivation'],
    hi: ['time management hindi'],
  },
}

// Throws on any lookup failure — a silently-skipped chunk would let
// already-known/already-dismissed channel_ids slip past the exclusion
// filter and get re-suggested.
async function chunkedExisting(supabase: any, table: string, ids: string[]): Promise<Set<string>> {
  const known = new Set<string>()
  const CHUNK = 200
  for (let i = 0; i < ids.length; i += CHUNK) {
    const chunk = ids.slice(i, i + CHUNK)
    const { data, error } = await supabase.from(table).select('channel_id').in('channel_id', chunk)
    if (error) throw new Error(`${table} lookup failed: ${error.message}`)
    for (const r of data || []) known.add((r as any).channel_id)
  }
  return known
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const authHeader = req.headers.get('Authorization')
  if (!authHeader) return json({ error: 'missing auth' }, 401)

  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  })

  const { data: { user }, error: userErr } = await supabase.auth.getUser()
  if (userErr || !user) return json({ error: 'unauthorized' }, 401)

  const { data: isAdmin, error: adminErr } = await supabase.rpc('is_admin')
  if (adminErr || !isAdmin) return json({ error: 'admin only' }, 403)

  let body: { category?: string; languages?: string[]; pageTokens?: Record<string, string> }
  try {
    body = await req.json()
  } catch {
    return json({ error: 'invalid body' }, 400)
  }

  const category = body.category
  const categoryQueries = category ? CATEGORIES[category] : undefined
  if (!category || !categoryQueries) {
    return json({ error: 'Unknown category', valid_categories: Object.keys(CATEGORIES) }, 400)
  }

  const languages = (Array.isArray(body.languages) ? body.languages : []).filter((l) => VALID_LANGUAGES.includes(l))
  if (!languages.length) {
    return json({ error: 'At least one valid language is required', valid_languages: VALID_LANGUAGES }, 400)
  }

  const queries = Array.from(new Set(languages.flatMap((l) => categoryQueries[l] || [])))
  if (!queries.length) {
    return json({ category, found: 0, inserted: 0, failed_queries: 0, next_page_tokens: {}, has_more: false })
  }

  // Each query string has its own independent YouTube pageToken cursor — the
  // caller (admin.html) stores next_page_tokens from a response and passes
  // it back as pageTokens on the next "load more" call to resume where each
  // query left off, instead of re-fetching the same first page.
  const incomingTokens = body.pageTokens && typeof body.pageTokens === 'object' ? body.pageTokens : {}

  const candidates = new Map<string, { channel_title: string; channel_photo: string | null; channel_bio: string; source_query: string }>()
  const nextPageTokens: Record<string, string> = {}
  let failedQueries = 0
  let lastError: string | null = null

  for (const q of queries) {
    // A query with no page token on a "load more" call has already been
    // exhausted (no next page from a previous run) — skip it.
    if (body.pageTokens && !incomingTokens[q]) continue

    const params = new URLSearchParams({
      part: 'snippet',
      type: 'channel',
      q,
      maxResults: '50',
      key: YOUTUBE_API_KEY,
    })
    if (incomingTokens[q]) params.set('pageToken', incomingTokens[q])
    const res = await fetch(`https://www.googleapis.com/youtube/v3/search?${params}`)
    const data = await res.json()
    if (!res.ok) {
      failedQueries++
      lastError = data?.error?.message || `HTTP ${res.status}`
      continue // one bad query shouldn't kill the whole run — but if ALL fail, that's surfaced below
    }
    if (data.nextPageToken) nextPageTokens[q] = data.nextPageToken
    for (const item of data.items || []) {
      const channelId = item.snippet?.channelId || item.id?.channelId
      if (!channelId || candidates.has(channelId)) continue
      candidates.set(channelId, {
        channel_title: item.snippet.channelTitle || item.snippet.title || channelId,
        channel_photo: item.snippet.thumbnails?.medium?.url || item.snippet.thumbnails?.default?.url || null,
        channel_bio: (item.snippet.description || '').slice(0, 500),
        source_query: q,
      })
    }
  }

  const hasMore = Object.keys(nextPageTokens).length > 0

  // Every single query failing (bad/revoked key, exhausted quota, etc.) must
  // surface as an error, not a fake "0 found" success — otherwise this looks
  // identical to a legitimately quiet search from the admin's side.
  if (failedQueries === queries.length) {
    return json({ error: 'YouTube API error — all search queries failed', detail: lastError }, 502)
  }

  if (!candidates.size) return json({ category, found: 0, inserted: 0, failed_queries: failedQueries, next_page_tokens: nextPageTokens, has_more: hasMore, candidates: [] })

  const allIds = Array.from(candidates.keys())
  let knownChannels: Set<string>, knownSuggestions: Set<string>
  try {
    ;[knownChannels, knownSuggestions] = await Promise.all([
      chunkedExisting(supabase, 'yt_channels', allIds),
      chunkedExisting(supabase, 'yt_channel_suggestions', allIds),
    ])
  } catch (e) {
    return json({ error: 'DB lookup failed', detail: (e as Error).message }, 500)
  }

  const rows = Array.from(candidates.entries())
    .filter(([id]) => !knownChannels.has(id) && !knownSuggestions.has(id))
    .map(([channel_id, c]) => ({ channel_id, ...c, category }))

  if (!rows.length) return json({ category, found: candidates.size, inserted: 0, failed_queries: failedQueries, next_page_tokens: nextPageTokens, has_more: hasMore, candidates: [] })

  const { error: insErr } = await supabase.from('yt_channel_suggestions').insert(rows)
  if (insErr) return json({ error: 'DB insert failed', detail: insErr.message }, 500)

  // Return the actual new rows (not just a count) so the admin panel can
  // append them straight to the list it already has on screen, instead of
  // re-querying and re-rendering everything in discovered_at order — which
  // would push the newly-inserted rows to the top and visibly reshuffle
  // whatever the admin was already looking at while scrolling.
  return json({ category, found: candidates.size, inserted: rows.length, failed_queries: failedQueries, next_page_tokens: nextPageTokens, has_more: hasMore, candidates: rows })
})
