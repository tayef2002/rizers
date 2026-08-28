// Server-side fetch of a YouTube channel + its recent uploads, for the admin
// panel's "Add Channel" flow (admin.html, RizPlay tab). The YouTube API key
// lives only here (YOUTUBE_API_KEY secret) — it never reaches the browser.
// Callers must be an authenticated admin (checked via the is_admin() RPC).
// This does NOT write anything to the database — it only returns a preview.
// The actual approve/reject write happens via the admin_decide_channel() RPC
// (scripts/db-fixes/yt_channels_curation.sql), called directly from
// admin.html with the admin's own session.
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

// Accepts a bare handle, an @handle, a full youtube.com/@handle or
// youtube.com/channel/UC... link, or a raw channel ID. Legacy /c/ and /user/
// custom URLs aren't resolvable via the v3 API the same way — callers should
// use the @handle instead.
function parseChannelInput(raw: string): { forHandle?: string; id?: string } | null {
  let s = (raw || '').trim()
  if (!s) return null
  s = s.replace(/^https?:\/\/(www\.)?youtube\.com\//i, '')
  s = s.replace(/^https?:\/\/(www\.)?youtu\.be\//i, '')
  s = s.split('?')[0].replace(/\/+$/, '')
  if (/^channel\//i.test(s)) {
    const id = s.split('/')[1]
    return id ? { id } : null
  }
  if (s.startsWith('@')) return { forHandle: s.slice(1).split('/')[0] }
  if (/^UC[\w-]{22}$/.test(s)) return { id: s }
  if (/^[\w.-]+$/.test(s)) return { forHandle: s }
  return null
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

  let body: { handle?: string }
  try {
    body = await req.json()
  } catch {
    return json({ error: 'invalid body' }, 400)
  }

  const parsed = parseChannelInput(body.handle || '')
  if (!parsed) {
    return json({ error: 'Could not read a channel from that — paste an @handle or a youtube.com/@handle or /channel/UC... link.' }, 400)
  }

  const chanParams = new URLSearchParams({ part: 'snippet,contentDetails', key: YOUTUBE_API_KEY })
  if (parsed.forHandle) chanParams.set('forHandle', parsed.forHandle)
  else chanParams.set('id', parsed.id!)

  const chanRes = await fetch(`https://www.googleapis.com/youtube/v3/channels?${chanParams}`)
  const chanData = await chanRes.json()
  if (!chanRes.ok) return json({ error: 'YouTube API error', detail: chanData?.error?.message || null }, 502)
  if (!chanData.items || !chanData.items.length) return json({ error: 'Channel not found' }, 404)

  const channel = chanData.items[0]
  const channelId = channel.id
  const channelTitle = channel.snippet.title
  const channelPhoto = channel.snippet.thumbnails?.medium?.url || channel.snippet.thumbnails?.default?.url || null
  const channelBio = channel.snippet.description || ''
  // customUrl is only a real @handle on channels that have claimed YouTube's newer handle
  // system — older custom URLs come back as "c/name" or "user/name" with no leading @, which
  // aren't usable as a stable unique identifier the same way, so those are left unset rather
  // than stored as a handle. Lowercased to match how profiles.username is stored/looked-up.
  const rawCustomUrl: string | undefined = channel.snippet.customUrl
  const channelHandle = rawCustomUrl && rawCustomUrl.startsWith('@') ? rawCustomUrl.slice(1).toLowerCase() : null
  const uploadsPlaylistId = channel.contentDetails.relatedPlaylists.uploads

  // Page through the ENTIRE uploads playlist (not just the most recent batch) —
  // approving a channel is meant to bring in all of its videos, however many
  // that is. Capped only as a safety backstop against a truly pathological
  // channel size, not as a normal limit.
  const PAGE_SAFETY_CAP = 3000
  const items: any[] = []
  let pageToken: string | undefined
  do {
    const plParams = new URLSearchParams({
      part: 'snippet,contentDetails',
      playlistId: uploadsPlaylistId,
      maxResults: '50',
      key: YOUTUBE_API_KEY,
    })
    if (pageToken) plParams.set('pageToken', pageToken)
    const plRes = await fetch(`https://www.googleapis.com/youtube/v3/playlistItems?${plParams}`)
    const plData = await plRes.json()
    if (!plRes.ok) return json({ error: 'YouTube API error', detail: plData?.error?.message || null }, 502)
    items.push(...(plData.items || []))
    pageToken = plData.nextPageToken
  } while (pageToken && items.length < PAGE_SAFETY_CAP)
  const capped = items.length >= PAGE_SAFETY_CAP

  const videoIds = items.map((it: any) => it.contentDetails.videoId).filter(Boolean)

  // Chunk the existing-video lookup — a large channel can have thousands of
  // IDs, which would otherwise blow past PostgREST's URL length for an
  // `in.(...)` filter in one shot.
  let existingMap = new Map<string, string>()
  const CHUNK = 200
  for (let i = 0; i < videoIds.length; i += CHUNK) {
    const chunk = videoIds.slice(i, i + CHUNK)
    const { data: existing, error: existErr } = await supabase
      .from('yt_videos')
      .select('video_id, filter_status')
      .in('video_id', chunk)
    if (existErr) return json({ error: 'DB lookup failed', detail: existErr.message }, 500)
    for (const r of existing || []) existingMap.set((r as any).video_id, (r as any).filter_status)
  }

  const { data: existingChannel } = await supabase
    .from('yt_channels')
    .select('curation_status')
    .eq('channel_id', channelId)
    .maybeSingle()

  const videos = items.map((it: any) => ({
    video_id: it.contentDetails.videoId,
    title: it.snippet.title,
    description: (it.snippet.description || '').slice(0, 500),
    thumbnail: it.snippet.thumbnails?.medium?.url || it.snippet.thumbnails?.default?.url || null,
    published_at: it.contentDetails.videoPublishedAt || it.snippet.publishedAt,
    already_known: existingMap.has(it.contentDetails.videoId),
    existing_filter_status: existingMap.get(it.contentDetails.videoId) || null,
  }))

  return json({
    channel: {
      channel_id: channelId,
      channel_title: channelTitle,
      channel_photo: channelPhoto,
      channel_bio: channelBio,
      channel_handle: channelHandle,
    },
    existing_curation_status: existingChannel?.curation_status || null,
    videos,
    new_video_count: videos.filter((v) => !v.already_known).length,
    capped,
  })
})
