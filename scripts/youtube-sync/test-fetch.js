// Step 1 test: confirm the YouTube API key works and can fetch a channel's videos.
// Usage: node test-fetch.js @channelhandle
// No Supabase writes yet — this just prints what it finds so we can check it's correct.

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
  const handle = process.argv[2];
  if (!handle) {
    console.error('Usage: node test-fetch.js @channelhandle');
    process.exit(1);
  }

  // Step A: resolve the channel handle to its channel ID + uploads playlist ID
  const chanUrl = `https://www.googleapis.com/youtube/v3/channels?part=snippet,contentDetails&forHandle=${encodeURIComponent(handle.replace(/^@/, ''))}&key=${apiKey}`;
  const chanRes = await fetch(chanUrl);
  const chanData = await chanRes.json();
  if (!chanData.items || !chanData.items.length) {
    console.error('Channel not found. Response:', JSON.stringify(chanData, null, 2));
    return;
  }
  const channel = chanData.items[0];
  const uploadsPlaylistId = channel.contentDetails.relatedPlaylists.uploads;
  console.log('✅ Channel found:', channel.snippet.title);
  console.log('   Channel ID:', channel.id);
  console.log('   Uploads playlist:', uploadsPlaylistId);

  // Step B: fetch the latest videos from the uploads playlist
  const plUrl = `https://www.googleapis.com/youtube/v3/playlistItems?part=snippet,contentDetails&playlistId=${uploadsPlaylistId}&maxResults=5&key=${apiKey}`;
  const plRes = await fetch(plUrl);
  const plData = await plRes.json();
  if (!plData.items) {
    console.error('Could not fetch videos. Response:', JSON.stringify(plData, null, 2));
    return;
  }
  console.log(`\n✅ Latest ${plData.items.length} videos:`);
  plData.items.forEach((item, i) => {
    console.log(`${i + 1}. ${item.snippet.title} (video ID: ${item.contentDetails.videoId})`);
  });
}

main().catch(err => console.error('Error:', err));
