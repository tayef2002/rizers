# Hadi — Rizers AI Life Partner
## Full Brainstorm & System Plan

---

## Vision

Hadi is not a chatbot. Hadi is a **living AI partner** inside Rizers who knows everything about you — your goals, habits, namaz, journal, finance, streaks — and guides you every single day like a real friend who never forgets, never judges, and always shows up.

Market mein GPT ache, Claude ache, Gemini ache — but **kono AI nei jo tomar poorer namaz er log dekhe, tomar journal er mood bujhe, tomar 21-day streak jante pare, ar shob kichu milie tomar jonno personalized guidance dite pare.**

Hadi sheta kore.

---

## Core Identity

| Property | Value |
|---|---|
| Name | **Hadi** (আরবি: পথপ্রদর্শক) |
| Personality | Caring + Disciplined. Bhai/Bon er moto — honest, warm, never preachy |
| Language | User je vashay likhe she vashay reply dibe. Tone: natural Banglish |
| Avatar | Unique Hadi avatar — Rizers brand er shathe match kore |
| Location | Knokz chat list e **pinned at top**, always visible |

---

## What Makes Hadi Different

| Feature | ChatGPT | Siri/Google | **Hadi** |
|---|---|---|---|
| Jante generic knowledge | ✅ | ✅ | ✅ |
| Tomar personal data jane | ❌ | ❌ | ✅ |
| Proactive message pathay | ❌ | ❌ | ✅ |
| Namaz/Islamic context jane | ❌ | ❌ | ✅ |
| Tomar mood/journal bujhe | ❌ | ❌ | ✅ |
| Action nite pare (with permission) | ❌ | Partially | ✅ |
| Tomar Rizers tools e connected | ❌ | ❌ | ✅ |

---

## Data Access (100% Personalized)

Hadi Supabase theke real-time user data access korbe:

### Spiritual
- Namaz logs (kon wakto miss hoyeche, streak koto din)
- Fasting logs (voluntary/Ramadan)
- Dua & reflection notes

### Productivity
- Goals (adult_goals) — progress, deadline
- Habits (adult_habits) — streak, completion rate
- Todo tasks — pending, overdue
- Deep work sessions — focus time
- Smart notes & journal entries

### Health & Life
- Sleep tracker
- Screen time logs
- Finance transactions (income/expense patterns)

### Social
- Community posts (ki share koreche, engagement)
- Streak cards (community te ki celebrate koreche)

### Kids (if parent)
- Kids er namaz, quran, habit progress

### Local Data (localStorage)
- Jei tools er jonno Supabase nei shetar data o Hadi janbe
- App settings, preferences

**❌ Exception:** Knokz chat conversations — private, Hadi dekhe na.

---

## How Hadi Works — The Intelligence Loop

```
Every Day:
1. Hadi checks all user data (Supabase + local)
2. Analyzes patterns: what's going well, what's slipping
3. Morning: sends personalized wake-up message
4. Throughout day: context-aware nudges
5. Night: reflection + tomorrow's plan
6. User can message Hadi anytime → instant response
```

### Data Pattern Examples

**Pattern detected:** 3 din dhore Fajr miss + journal e "tired" likheche
**Hadi says:** "Bhai, last 3 dine Fajr ta miss hoyeche — ar journal e dekhlam tumi tired feel kortecho. Kal raat e ki arektu agey ghumano try korbo? Ami reminder set kore dite pari."

**Pattern detected:** 18-day streak active, 2 din bake
**Hadi says:** "Mindblowing! 18 days streak active ache. Matro 2 din baki — ei 2 din tumi complete korle Rizers history te name uthe jabe. Kal er habit ta confirm korbo?"

**Pattern detected:** Goal set koreche "Quran khatam" but 2 soptah theke kono progress nei
**Hadi says:** "Tomar 'Quran khatam' goal ta 2 soptah dhore update hoyni. Pressure dibo na — but jodi chao ami ekta chhoto daily plan baniye dite pari. Raji?"

---

## UI Design — Hadi Chat

### Knokz Chat List
- Hadi pinned at **absolute top** — always
- Special avatar: Hadi logo (not a person photo)
- Badge shows unread messages from Hadi
- Slightly different row styling — gold/orange accent

### Inside Hadi Conversation
- **Hadi bubbles:** Different color (dark/branded), left side
- **User bubbles:** Normal, right side
- **Data Cards:** Special rich cards inline in chat
  - Streak card: "21 days 🔥"
  - Weekly summary card
  - Goal progress bar
  - Habit completion ring
- **Quick action buttons:** "হ্যাঁ করো" / "পরে" / "আরো দেখাও"
- **No timestamp clutter** — clean minimal UI
- Typing indicator when Hadi is thinking

### Special Hadi Header
```
[Hadi Avatar] Hadi          [Settings icon]
              Your AI Partner
              ● Online always
```

---

## Proactive Messages — Daily Flow

### Morning (Fajr time)
"Assalamu Alaikum! আজ নতুন দিন। 
তোমার আজকের top priority: [Goal name]
Fajr ki পড়েছ? ✅"

### Mid-morning (9-10 AM)
"আজকের habit checklist ready?
→ [Habit 1] ⬜
→ [Habit 2] ⬜
চাইলে এখনই শুরু করো!"

### Afternoon (slump time, 2-3 PM)
"Post-lunch energy drop normal. 
তোমার Deep Work timer চালু করবো? 25 min?"

### Evening
"আজ [X] টা habit complete করেছ 🎯
[Motivational data insight]"

### Night (before sleep)
"আজকের দিনটা কেমন গেল?
Journal এ লিখবে? নাকি voice note দেবে?"

---

## Action System (Option B — Permission Based)

Hadi suggest করবে → User approve করবে → Hadi execute করবে

### Actions Hadi নিতে পারবে:
- ✅ Habit mark as complete
- ✅ Todo task create/complete
- ✅ Goal progress update
- ✅ Namaz log করা
- ✅ Fasting log করা
- ✅ Journal entry create
- ✅ Reminder/alarm set
- ✅ Deep work timer start
- ✅ Finance transaction log

### Flow:
```
Hadi: "তোমার আজকের Fajr log করে দিই?"
User: "হ্যাঁ"
Hadi: ✅ Done → Supabase update → "Done! BarakAllah."
```

Hadi যা করে সব user কে জানায়। No silent actions.

---

## Onboarding — First Time Experience

User register করার সাথে সাথে Hadi নিজে থেকে message পাঠাবে:

```
Hadi: "Assalamu Alaikum! আমি Hadi — তোমার Rizers AI partner।
আমি তোমার সাথে সবসময় থাকবো।
তোমাকে কিছু জিজ্ঞেস করি?"

→ [শুরু করি] button
```

**Onboarding questions (conversational, not form):**
1. তোমার বয়স কত? (personalization)
2. তুমি কি নামাজ পড়? (Islamic features on/off)
3. তোমার সবচেয়ে বড় চ্যালেঞ্জ কী? (focus area)
4. দিনের কোন সময়টা তোমার productive? (notification timing)
5. তুমি কি অভিভাবক? (kids module)

এরপর Hadi বলে:
"Perfect! আমি সব বুঝে গেছি। চলো শুরু করি।"
→ App setup complete — no manual configuration needed.

---

## Native App — "Hey Hadi" Wake Word

**Phase 1 (Web):** Knokz e Hadi chat
**Phase 2 (Native App):** Voice wake word

```
User: "Hey Hadi"
Hadi: "বলো?"
User: "আজকের Fajr log করো"
Hadi: "Done! BarakAllah fi umrik."
```

- Works screen off
- Works in any other app
- Uses: Picovoice Porcupine (wake word) + Groq Whisper (STT) + LLM
- Play Store / App Store এ launch হবে

---

## Technical Architecture

### Current (Web)
```
User message → Knokz Hadi conversation
→ Groq API (llama-3.1-70b)
→ System prompt: user er full data as context
→ Response → Hadi bubble
→ If action needed → Supabase update
```

### System Prompt Structure
```
You are Hadi, the AI life partner for [User Name] on Rizers.

USER PROFILE:
- Name: [name], Age: [age]
- Goals: [list]
- Today's habits: [status]
- Namaz today: [status]
- Current streak: [X days]
- Journal mood (last 3 days): [data]
- Finance this month: [summary]
- [... all data ...]

PERSONALITY:
- Warm, caring, like a close friend
- Never preachy or lecture
- Data-driven suggestions only
- Always transparent about actions
- Language: match user's language, Banglish tone

RULES:
- Never make up data
- Always ask before taking action
- Tell user what you did after action
- Keep messages short and human
```

### Proactive Messages
```
Cron job (server-side):
→ Every morning: fetch user data → generate message → push to Hadi conversation
→ Pattern detection: check for slipping habits, upcoming deadlines, streak milestones
→ Push notification to device
```

---

## Why This Wins The Market

1. **GPT জানে না তুমি আজ Fajr পড়েছ কিনা। Hadi জানে।**
2. **Siri জানে না তোমার 18-day streak আছে। Hadi জানে।**
3. **কোনো app তোমাকে manage করে না। Hadi করে।**
4. **User কে কিছু বুঝতে হয় না। Hadi নিজেই বুঝিয়ে দেয়।**
5. **"Hey Hadi" — tomar phone e tomar personal AI, always on.**

---

## Phases

### Phase 1 — MVP (Web, now)
- [ ] Hadi pinned in Knokz
- [ ] Special Hadi chat UI
- [ ] Basic Q&A with user data context
- [ ] Morning proactive message (manual trigger)
- [ ] Onboarding conversation

### Phase 2 — Smart (Web, 1-2 months)
- [ ] Full data context in every message
- [ ] Pattern detection & smart nudges
- [ ] Action execution (habit log, namaz log, etc.)
- [ ] Data cards in chat
- [ ] Cron-based daily messages

### Phase 3 — Native App
- [ ] React Native / Flutter app
- [ ] "Hey Hadi" wake word
- [ ] Background proactive notifications
- [ ] Voice-first interface
- [ ] Play Store + App Store launch

---

## One Line Pitch

> "Rizers এ Hadi আছে — সে তোমার সব data জানে, তোমাকে কখনো ভুলে না, আর তোমার জীবনটা manage করে যাতে তুমি শুধু জীবনটা enjoy করতে পারো।"

---

*Brainstormed: 2026-07-15*
*Next step: Phase 1 implementation*
