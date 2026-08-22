// Fetches a channel's latest videos from YouTube and stores them in Supabase.
// Usage: node sync-channel.js @channelhandle
// This is the MVP path — no Groq scoring yet (added later once the multi-channel
// pipeline is built). Videos are marked filter_status='approved' so they show up
// in the RizPlay feed immediately.

const fs = require('fs');
const path = require('path');

function loadEnv() {
  const envPath = path.join(__dirname, '.env');
  const lines = fs.readFileSync(envPath, 'utf8').split('\n');
  const env = {};
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const idx = trimmed.indexOf('=');
    if (idx === -1) continue;
    env[trimmed.slice(0, idx)] = trimmed.slice(idx + 1);
  }
  return env;
}

async function main() {
  const env = loadEnv();
  const apiKey = env.YOUTUBE_API_KEY;
  const supabaseUrl = env.SUPABASE_URL;
  const serviceKey = env.SUPABASE_SERVICE_ROLE_KEY;
  const handle = process.argv[2];
  if (!handle) {
    console.error('Usage: node sync-channel.js @channelhandle');
    process.exit(1);
  }

  // Step A: resolve channel
  const chanUrl = `https://www.googleapis.com/youtube/v3/channels?part=snippet,contentDetails&forHandle=${encodeURIComponent(handle.replace(/^@/, ''))}&key=${apiKey}`;
  const chanRes = await fetch(chanUrl);
  const chanData = await chanRes.json();
  if (!chanData.items || !chanData.items.length) {
    console.error('Channel not found. Response:', JSON.stringify(chanData, null, 2));
    return;
  }
  const channel = chanData.items[0];
  const channelId = channel.id;
  const channelTitle = channel.snippet.title;
  const channelPhoto = channel.snippet.thumbnails.medium?.url || channel.snippet.thumbnails.default?.url;
  const channelBio = channel.snippet.description || '';
  const uploadsPlaylistId = channel.contentDetails.relatedPlaylists.uploads;

  // Step B: fetch latest videos
  const plUrl = `https://www.googleapis.com/youtube/v3/playlistItems?part=snippet,contentDetails&playlistId=${uploadsPlaylistId}&maxResults=15&key=${apiKey}`;
  const plRes = await fetch(plUrl);
  const plData = await plRes.json();
  if (!plData.items) {
    console.error('Could not fetch videos. Response:', JSON.stringify(plData, null, 2));
    return;
  }

  // Step C: upsert channel into Supabase
  const chanUpsertRes = await fetch(`${supabaseUrl}/rest/v1/yt_channels?on_conflict=channel_id`, {
    method: 'POST',
    headers: {
      'apikey': serviceKey,
      'Authorization': `Bearer ${serviceKey}`,
      'Content-Type': 'application/json',
      'Prefer': 'resolution=merge-duplicates'
    },
    body: JSON.stringify({
      channel_id: channelId,
      channel_title: channelTitle,
      channel_photo: channelPhoto,
      channel_bio: channelBio,
      status: 'live' // this channel's owner is the one running this script — self-consent
    })
  });
  if (!chanUpsertRes.ok) {
    console.error('Channel upsert failed:', await chanUpsertRes.text());
    return;
  }
  console.log('✅ Channel synced:', channelTitle);

  // Step D: upsert videos into Supabase
  const videoRows = plData.items.map(item => ({
    video_id: item.contentDetails.videoId,
    channel_id: channelId,
    channel_title: channelTitle,
    channel_photo: channelPhoto,
    title: item.snippet.title,
    description: item.snippet.description,
    thumbnail: item.snippet.thumbnails.medium?.url || item.snippet.thumbnails.default?.url,
    published_at: item.contentDetails.videoPublishedAt || item.snippet.publishedAt,
    filter_status: 'approved'
  }));

  const vidUpsertRes = await fetch(`${supabaseUrl}/rest/v1/yt_videos?on_conflict=video_id`, {
    method: 'POST',
    headers: {
      'apikey': serviceKey,
      'Authorization': `Bearer ${serviceKey}`,
      'Content-Type': 'application/json',
      'Prefer': 'resolution=merge-duplicates'
    },
    body: JSON.stringify(videoRows)
  });
  if (!vidUpsertRes.ok) {
    console.error('Video upsert failed:', await vidUpsertRes.text());
    return;
  }
  console.log(`✅ ${videoRows.length} videos synced to Supabase.`);
}

main().catch(err => console.error('Error:', err));
