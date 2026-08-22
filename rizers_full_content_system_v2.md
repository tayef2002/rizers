# 🎥 RIZERS — YouTube Content Sync & Creator Growth System
### By Tayef | Rizers
### Full Blueprint (Claude Code Reference File)

---

## 🎯 মূল সমস্যা যেটা সমাধান করা হচ্ছে

RIZERS feed শুরুতে content-poor থাকবে কারণ content creator রা নতুন platform এ নিজে থেকে content দিতে চাইবে না (audience/proof না দেখে)। তাই YouTube থেকে relevant, vision-aligned content auto-sync করে feed ভরে রাখা হবে, পাশাপাশি creator দের organically এবং data-backed ভাবে RIZERS এ আনার একটা growth system বানানো হচ্ছে।

---

## 1️⃣ CONTENT SELECTION (Cold Start Strategy)

- সব YouTube content sync করা হবে না — শুরুতে **১০০টা curated channel** manually বেছে নেওয়া হবে
- Selection criteria: Islamic values, productivity, discipline, self-improvement, parenting — RIZERS vision এর সাথে যা মেলে
- **Phase A:** প্রথমে শুধু এই ১০০ channel এর content **cycle/preview** আকারে দেখানো হবে (পুরোপুরি backfill না)
- **Phase B:** পরে ধীরে ধীরে এই একই ১০০ channel এর **পুরো content library sync** শুরু হবে (in sha Allah)
- **Phase C:** এরপর থেকে প্রতিদিন/নিয়মিত interval এ নতুন uploaded video ও auto-check হয়ে feed এ যোগ হবে

---

## 2️⃣ YOUTUBE DATA API — QUOTA MATH (বিস্তারিত, ভুল বোঝাবুঝি এড়াতে)

### পারমিশন বনাম Quota — দুইটা আলাদা বিষয় (গুরুত্বপূর্ণ)

- **Permission:** YouTube এর যেকোনো **public channel** এর video তথ্য creator এর অনুমতি ছাড়াই আনা যায় — এখানে কোনো বাধা নেই।
- **Quota:** Google প্রতিটা app কে দিনে **১০,০০০ unit** (free tier default) দেয়। প্রতিটা API call এ কিছু unit খরচ হয়। Filter করা বা না করা — এই quota খরচে কোনো পার্থক্য হয় না, কারণ filter করার আগে video এর title/description আনতেই হবে (সেটাই মূল খরচ)।

### কোন API Call এ কত Unit লাগে

| API Call | Unit Cost | কী কাজে লাগে |
|---|---|---|
| `playlistItems.list` | ১ unit/call (৫০টা video পর্যন্ত একসাথে) | Channel এর video list আনা (সবচেয়ে সস্তা, efficient পদ্ধতি) |
| `videos.list` | ১ unit/call (৫০টা video পর্যন্ত) | Video এর details (duration, views, ইত্যাদি) আনা |
| `search.list` | ১০০ unit/call | Keyword দিয়ে video খোঁজা (এড়িয়ে চলা ভালো, খুব costly) |

**নিয়ম:** সবসময় `playlistItems.list` + `videos.list` ব্যবহার করতে হবে, `search.list` এড়িয়ে চলতে হবে (১০০ গুণ বেশি খরচ করে)।

### বাস্তব হিসাব — ১০০ Channel এর জন্য

**Daily Ongoing Check (Phase C — প্রতিদিন নতুন video আছে কিনা দেখা):**
```
১০০ channel × ১ unit (playlistItems.list call) = ~১০০-২০০ unit/day
→ ১০,০০০ unit বাজেটের মাত্র ~২% ব্যবহার হবে
```

**Full Backfill (Phase B — সব পুরনো video একসাথে আনা):**
```
ধরি: প্রতি channel এ গড়ে ৫০০টা video আছে
১০০ channel × ৫০০ video = ৫০,০০০ video

video list আনতে: ৫০,০০০ ÷ ৫০ (প্রতি call) = ১,০০০ call = ১,০০০ unit
video details আনতে: আরও ~১,০০০ call = ১,০০০ unit

মোট ≈ ২,০০০ unit — একদিনের ১০,০০০ বাজেটের মধ্যেই আরামে হয়ে যায়!
```

### ✅ সংক্ষেপে সিদ্ধান্ত

তোমার বর্তমান স্কেলে (১০০ channel) **quota কোনো বাধাই না** — efficient method (`playlistItems.list`) ব্যবহার করলে পুরো backfill ১ দিনেই সম্ভব, এবং daily ongoing check নগণ্য (~২%) খরচ করে। Batch/ধাপে ধাপে করার দরকার নেই এই scale এ। শুধু ভবিষ্যতে channel সংখ্যা হাজারে পৌঁছালে আবার হিসাব করে দেখতে হবে, এবং তখন প্রয়োজনে Google এর কাছে quota বাড়ানোর জন্য audit/application করা যায়।

---

## 3️⃣ FILTERING SYSTEM (2-Layer Approach) — AI Quota আলাদা

**গুরুত্বপূর্ণ:** এই filtering YouTube quota থেকে সম্পূর্ণ আলাদা একটা system (Groq API, নিজস্ব quota — দিনে ১৪,৪০০ request)।

### Layer 1 — Whitelist (Manual Control)
তুমি নিজে/team ১০০ trusted channel বেছে নিবে — source নিজেই reliable হওয়ায় এটাই সবচেয়ে শক্তিশালী filter।

### Layer 2 — AI Score (Groq দিয়ে, llama-3.1-8b-instant)
প্রতিটা video এর title + description AI কে score করানোর জন্য পাঠানো হবে:
```
System Prompt: "তুমি RIZERS app এর content curator। এই video টা RIZERS এর 
মিশনের সাথে (Islamic values + productivity + discipline + self-improvement) 
কতটা মিলে সেটা score করো ০-১০০। Entertainment-only, music video, 
controversial/political content, clickbait হলে score কম দাও।"

Output: {"score": 85, "category": "productivity", "reason": "..."}
```

| Score | Action |
|-------|--------|
| ৭০+ | Auto feed এ যোগ |
| ৪০-৭০ | Review Queue (তুমি manual approve/reject) |
| ৪০ এর নিচে | Discard |

**Quota Impact Table (পার্থক্য স্পষ্ট করার জন্য):**

| তুমি যা করো | YouTube Quota | Groq (AI) Quota |
|---|---|---|
| সব video fetch + AI filter করে আনো | খরচ হয় (আগের হিসাব অনুযায়ী) | খরচ হয় |
| সব video fetch করে, filter ছাড়াই সরাসরি feed এ দাও | খরচ হয় (**সমান, কোনো সাশ্রয় নেই**) | খরচ হয় **না** |

Filter বাদ দিলে YouTube quota তে কোনো সাশ্রয় হয় না (video fetch করতেই হয়), শুধু Groq quota বাঁচে — কিন্তু তখন অপ্রাসঙ্গিক content ঢুকে যাবে। তাই filter রাখাই উচিত।

---

## 4️⃣ DEMO CREATOR PROFILE SYSTEM

প্রতিটা synced channel এর জন্য একটা **auto-generated demo profile** তৈরি হবে:

- Creator নাম, photo, bio — YouTube থেকে auto-pull
- Status: **"Unclaimed"** — profile এ স্পষ্টভাবে লেখা থাকবে: *"এটি একটি Unclaimed Profile — YouTube থেকে auto-synced। এই creator এখনো RIZERS এ join করেননি।"* (Transparency জরুরি, impersonation এড়াতে)
- সব synced video RIZERS এর ভিতরেই **serial/organized ভাবে** (playlist স্টাইলে) দেখা যাবে, YouTube এ যাওয়া লাগবে না

---

## 5️⃣ "CONNECT RIZER" BUTTON

- Normal profile এ যেখানে Message/Chat button থাকে, Demo Profile এ সেই জায়গায় থাকবে **"Connect Rizer"** button
- এটা YouTube এর Subscribe / Facebook এর Follow এর মতো কাজ করে — কিন্তু কোনো live connection হয় না যতক্ষণ creator real account না বানায়
- Click করলে request `connect_requests` table এ জমা হবে

---

## 6️⃣ VOTING SYSTEM (Message Icon → Vote Icon এ পরিবর্তন)

- Demo Profile এ আগে যেখানে "কথা বলার" icon ছিল, সেটা এখন **Vote Button**
- User কে জিজ্ঞেস করা হবে: *"তুমি কি চাও এই creator RIZERS এ regular আসুক?"*
- **নিয়ম:** ১ Rizer = ১ Vote (duplicate vote block, unique constraint দিয়ে)
- **Vote count publicly profile এ দেখা যাবে** — যেমন: *"🗳️ 1,003 Rizer connect করতে চায়"*

```sql
votes table:
  - demo_profile_id
  - user_id (voter)
  - voted_at
  - UNIQUE(demo_profile_id, user_id)  -- duplicate vote block
```

---

## 7️⃣ CREATOR OUTREACH (দুই ভাবে ঘটতে পারে)

### A. তুমি নিজে Approach করবে (Direct Outreach)
Real vote data দেখিয়ে creator কে personally contact করবে:
> *"আসসালামু আলাইকুম, আমরা আপনার YouTube content RIZERS এ sync করে রেখেছিলাম, এর মধ্যে ১,০০০+ Rizer ভোট দিয়েছে যে তারা আপনাকে RIZERS এ regular দেখতে চায়। আপনি join করলে এই ১,০০০ user automatically আপনার সাথে connected হয়ে যাবে।"*

### B. Organic/Viral Loop (Public Vote Count এর কারণে)
- Public vote count দেখে creator এর **নিজের fan/follower** creator কে নিজে থেকেই বলতে পারে: *"ভাই দেখো RIZERS এ তোমাকে ১,০০০ মানুষ চায়, একাউন্ট claim করো!"*
- এটা creator এর কাছে third-party validation হয়ে যায়, sales pitch মনে হয় না — trust বেশি তৈরি হয়

**কেন এই strategy শক্তিশালী:**
- Social proof + FOMO তৈরি করে
- Ready-made audience দেখে creator নতুন platform এ আসতে ভয় পাবে না

---

## 8️⃣ CLAIM / MIGRATION PROCESS

```
তুমি manually verify করে creator এর জন্য real account বানাবে →
  → System automatically:
     - demo_profile এর সব connect_requests + votes → 
       real account এর actual follower/connection এ migrate
     - Status "Unclaimed" → "Claimed"
     - পুরনো video history অক্ষত থাকে, owner এখন real creator account
  → Creator তখন RIZERS এর সব feature ব্যবহার করতে পারবে 
    (post, content upload, analytics dashboard) + ready-made audience নিয়ে
```

---

## 9️⃣ AD/MONETIZATION বাস্তবতা

- YouTube embed player ব্যবহার করলে (legally required, raw download না), creator এর video তে monetization on থাকলে **সেই ad RIZERS এর ভিতরেও দেখাবে** — এটা bypass/block করা **সম্ভব কিন্তু করা উচিত না**:
  - YouTube ToS ভঙ্গ হবে → API access সম্পূর্ণ revoke হতে পারে
  - Creator দের ad revenue কেটে নেওয়া হচ্ছে জানলে তারা কখনো join করবে না
- **Positioning হিসেবে ব্যবহার করা ভালো:** *"এই content YouTube থেকে, creator এর ad revenue অক্ষত থাকে"* — এটা RIZERS কে honest partner হিসেবে দেখাবে
- ভবিষ্যতে creator claim করে সরাসরি RIZERS এ upload করলে, তখন RIZERS নিজস্ব monetization/ad-free অপশন দিতে পারবে (upgrade incentive)

---

## 🔟 CUSTOM PLAYER UI (RIZERS Feel)

### যা Customize করা যাবে (Full Freedom)
- Video card এর চারপাশের wrapper UI — creator info card, RIZERS branding, vote button, comment section
- RIZERS brand color (#1a6b3c) থিম, card shape, animation, thumbnail overlay, loading screen
- Autoplay/Next video logic — RIZERS এর নিজস্ব curated feed অনুযায়ী

### যা Customize করা যাবে না (YouTube Restriction)
- Player এর ভিতরের controls (play/pause, progress bar) — YouTube এর নিজস্ব design
- YouTube logo — `modestbranding=1` দিয়ে control bar থেকে কমানো যায়, কিন্তু ১০০% মুছে ফেলা যায় না; Google যেকোনো সময় এই behavior বদলাতে পারে
- `rel=0` দিলে end-screen এ শুধু same-channel video suggest হবে, সম্পূর্ণ বন্ধ হবে না

### Auto-Advance দিয়ে YouTube End-Screen Skip করা
```javascript
player.addEventListener('onStateChange', (event) => {
  if (event.data === YT.PlayerState.ENDED) {
    loadNextVideoFromRizersFeed(); // YouTube এর end-screen আসার আগেই
  }
});
```
Video শেষ হওয়া মাত্রই RIZERS নিজের feed থেকে পরের video load করে দেয়, ফলে user প্রায় কখনোই YouTube এর নিজস্ব end-screen/recommendation দেখবে না।

---

## 1️⃣1️⃣ TRANSCRIPT-BASED DEEP FILTERING (Phase 2/3 — আরও নির্ভুল Content Selection)

### কেন দরকার
শুধু title/description দেখে filter করলে ভুল হতে পারে — অনেক video এর title misleading হয়, আসল content বোঝা যায় না। Transcript (video এর ভিতরের কথা, লেখায় রূপান্তরিত) দেখলে AI অনেক বেশি নির্ভুলভাবে বুঝতে পারবে video টা সত্যিই RIZERS vision এর সাথে মেলে কিনা।

### Transcript কীভাবে পাওয়া যায়

**Official পদ্ধতি (সীমাবদ্ধ):**
- YouTube Data API তে `captions.list` + `captions.download` আছে, কিন্তু এটা ব্যবহার করতে সাধারণত video owner এর OAuth অনুমতি লাগে — Facebook এর মতোই restricted।

**Unofficial কিন্তু Widely-Used পদ্ধতি:**
- বেশিরভাগ video তে YouTube নিজেই auto-generated caption বানিয়ে রাখে
- এই caption একটা public URL (timedtext endpoint) থেকে fetch করা যায়, Data API quota খরচ ছাড়াই, owner এর অনুমতি ছাড়াই
- ⚠️ এটা "official documented" পদ্ধতি না — grey-area/community-accepted পদ্ধতি, YouTube যেকোনো সময় নোটিশ ছাড়া বন্ধ/পরিবর্তন করতে পারে

### Updated Filtering Flow (Transcript যোগ করে)

```
Video প্রথমে title/description দিয়ে Layer 1+2 filter পাশ করবে (আগের মতো)
  ↓
Pass করলে → Transcript fetch করা হবে (প্রথম ২-৩ মিনিট যথেষ্ট, 
             পুরো transcript token/cost বেশি খরচ করবে)
  ↓
Transcript + title + description → Groq কে একসাথে পাঠানো
  ↓
আরও নির্ভুল score পাওয়া যাবে (আসল বক্তব্য বুঝে, শুধু title না দেখে)
```

---

## 1️⃣2️⃣ PERSONALIZED RECOMMENDATION SYSTEM (Phase 3 — FB Algorithm এর ধাঁচে)

### মূল ধারণা
প্রতিটা user এর জন্য আলাদা ভাবে content সাজানো — একজন যা দেখতে চায় আরেকজনকে সেটা জোর করে দেখানো হবে না, বরং প্রত্যেকের activity অনুযায়ী personalized feed তৈরি হবে।

### কীভাবে কাজ করবে

```
প্রতিটা video এর transcript + metadata থেকে একটা "content profile" 
বানানো হবে (embedding vector — content এর মূল বিষয়বস্তু সংখ্যায় রূপান্তরিত)

User এর activity track করা হবে:
  - কোন content বেশি দেখেছে/সম্পূর্ণ দেখেছে
  - কোনটায় vote/like দিয়েছে
  - কোন category তে বেশি সময় কাটিয়েছে

Video profile + User profile মিলিয়ে match score বের করে 
সবচেয়ে relevant content আগে দেখানো হবে ব্যক্তি-ভিত্তিক ভাবে
```

এটাকে বলে **"content-based recommendation system"** — FB এর মতো পুরোপুরি জটিল না হলেও একই মূলনীতিতে কাজ করে।

### বাস্তবতা (Honest Note)
- Transcript fetch + AI processing প্রতিটা video তে extra cost/time যোগ করে — তাই পুরো transcript না পাঠিয়ে প্রথম কয়েক মিনিট যথেষ্ট
- Personalized recommendation বড় ও জটিল engineering কাজ — শুরুতে simple category-matching (rule-based) দিয়ে শুরু করে ধীরে ধীরে sophisticated করা বাস্তবসম্মত
- এই দুইটা feature (transcript filtering + personalization) **Phase 2/3 এ রাখা ভালো** — আগে core sync + basic title/description filter দিয়ে launch করে, পরে এই layer যোগ করা

---

| বিষয় | সীমাবদ্ধতা |
|------|-----------|
| YouTube API Quota | ১০০ channel scale এ বাধা না (উপরের হিসাব দেখুন); হাজার+ channel এ গেলে পুনরায় হিসাব করতে হবে |
| Video Hosting | Full download না, শুধু official embed player — legal safety এর জন্য বাধ্যতামূলক |
| AI Filtering Accuracy | ১০০% guarantee নেই — Review Queue দিয়ে শুরুতে trust build করা জরুরি |
| YouTube Branding | Logo/controls সম্পূর্ণ মুছে ফেলা যাবে না, শুধু কমানো যায় |
| Transcript Fetching | Unofficial পদ্ধতি — YouTube যেকোনো সময় বন্ধ/পরিবর্তন করতে পারে নোটিশ ছাড়া |
| Personalization | জটিল engineering কাজ — Phase 3 এ, simple rule-based দিয়ে শুরু করা ভালো |
| Transparency | Demo profile এ "Unclaimed" স্পষ্ট লেখা থাকা জরুরি — impersonation এড়ানোর জন্য |

---

*By Tayef | Rizers*
