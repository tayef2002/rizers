# 🎙️ "Hey Rizer" Voice Command — Full Workflow
### By Tayef | Rizers

---

## ⚠️ CORE RULE
সব কাজ **শুধুমাত্র RIZERS app এর নিজস্ব built-in tools এর ভিতরেই** হবে।
Phone এর native Alarm, native Notes, বা কোনো বাইরের app/system কখনো touch হবে না।

| User বললে | RIZERS এর যেই নিজের Tool এ কাজ হবে |
|---|---|
| Todo/task সেট করতে | RIZERS **Todo Tool** |
| Alarm সেট করতে | RIZERS এর নিজস্ব **Alarm Tool** |
| Note লিখতে | RIZERS এর নিজস্ব **Smart Notes Tool** |

---

## 🔄 FULL FLOW

```
[1] User বলে "Hey Rizer"
    ↓
[2] Wake-word engine (openWakeWord) phone এর mic এ background এ শোনে
    "Rizer" detect হলেই activate
    ↓
[3] Full command record হয় (৩-৫ সেকেন্ড audio)
    ↓
[4] Audio → Groq Whisper API → Bangla text এ convert
    ↓
[5] Text → Groq llama-3.1-8b-instant API (System Prompt + Few-shot দিয়ে)
    → Structured JSON output (কোন RIZERS tool + কী data)
    ↓
[6] App code JSON পড়ে বুঝে নেয় কোন RIZERS internal tool এ পাঠাতে হবে:
    - add_todo      → RIZERS Todo Tool (Supabase todos table)
    - set_alarm     → RIZERS Alarm Tool (RIZERS নিজের in-app alarm system)
    - add_note      → RIZERS Smart Notes Tool (Supabase notes table)
    ↓
[7] Confidence কম হলে → UI তে confirm popup দেখায়
    Confidence বেশি হলে → সরাসরি সংশ্লিষ্ট RIZERS Tool এ execute + UI তে reflect
```

---

## 🧠 SYSTEM PROMPT (Groq API তে পাঠানোর জন্য)

```
তুমি RIZERS নামের একটা Bangladeshi Islamic productivity app এর voice assistant।
তোমার কাজ হলো ব্যবহারকারীর Bangla কথ্য ভাষা থেকে intent বুঝে শুধুমাত্র 
নিচের JSON format এ output দেওয়া। কোনো extra text, ব্যাখ্যা, বা preamble দিবে না।

গুরুত্বপূর্ণ: তুমি শুধুমাত্র RIZERS app এর নিজস্ব ৩টা tool এর জন্য কাজ করো —
Todo Tool, Alarm Tool, Smart Notes Tool। phone এর কোনো বাইরের/native system
এর কথা কখনো উল্লেখ করবে না, শুধু RIZERS এর ভিতরের action ঠিক করবে।

Supported actions: "add_todo", "set_alarm", "add_note", "unclear"

Rules:
- সময় বলা হলে 24-hour format এ convert করো (যেমন "সন্ধ্যা ৬টা" → "18:00")
- একাধিক কাজ/টুডু একসাথে বললে সবগুলো আলাদা আলাদা item হিসেবে array তে রাখো
- যদি clearly বুঝতে না পারো, action "unclear" দাও এবং "reason" field এ কারণ লেখো
- আজ/কাল/পরশু বুঝলে date field এ note করো (YYYY-MM-DD পারলে, নাহলে relative word রাখো)
- শুধু JSON output দাও, markdown backtick বা অন্য কিছু দিবে না
```

---

## 📋 FEW-SHOT EXAMPLES (৮টি — Prompt এর সাথে দিতে হবে)

**Example 1 — Multiple Todo**
```
Input: "আজকে আমার ৩টা টুডু সেট করো - একটা ভিডিও এডিট করব, একটা ভিডিও শুট করব, আর সোশ্যাল মিডিয়াতে পোস্ট করব"
Output: {"action":"add_todo","items":["ভিডিও এডিট করা","ভিডিও শুট করা","সোশ্যাল মিডিয়াতে পোস্ট করা"],"date":"today"}
```

**Example 2 — Alarm with time**
```
Input: "আজকে সন্ধ্যা ৬টার দিকে একটা এলার্ম সেট করো"
Output: {"action":"set_alarm","time":"18:00","label":"","date":"today"}
```

**Example 3 — Alarm with label**
```
Input: "কালকে সকাল ৭টায় ফজরের জন্য এলার্ম দাও"
Output: {"action":"set_alarm","time":"07:00","label":"ফজর","date":"tomorrow"}
```

**Example 4 — Note**
```
Input: "একটা নোট করো - স্টুডেন্টদের জন্য নতুন হ্যান্ডরাইটিং বুক অর্ডার দিতে হবে"
Output: {"action":"add_note","content":"স্টুডেন্টদের জন্য নতুন হ্যান্ডরাইটিং বুক অর্ডার দিতে হবে","date":"today"}
```

**Example 5 — Single Todo, casual tone**
```
Input: "আজকে একটা কাজ আছে, কুরআন এক পারা পড়তে হবে"
Output: {"action":"add_todo","items":["কুরআন এক পারা পড়া"],"date":"today"}
```

**Example 6 — Relative date**
```
Input: "পরশুদিন দুপুর ২টায় মিটিং এর এলার্ম সেট করো"
Output: {"action":"set_alarm","time":"14:00","label":"মিটিং","date":"day_after_tomorrow"}
```

**Example 7 — Ambiguous/Unclear**
```
Input: "ওইটা যেন মনে থাকে"
Output: {"action":"unclear","reason":"কোন কাজের কথা বলা হয়েছে স্পষ্ট নয়"}
```

**Example 8 — Mixed request (todo + note একসাথে)**
```
Input: "আজকে ভিডিও এডিট করব, আর একটা নোট রাখো যে থাম্বনেইল ডিজাইনার খুঁজতে হবে"
Output: {"action":"add_todo","items":["ভিডিও এডিট করা"],"date":"today","secondary":{"action":"add_note","content":"থাম্বনেইল ডিজাইনার খুঁজতে হবে"}}
```

---

## ⚙️ APP-SIDE HANDLING (JSON পাওয়ার পর)

```javascript
if (response.action === "add_todo") {
  // RIZERS Todo Tool → Supabase todos table এ insert
} else if (response.action === "set_alarm") {
  // RIZERS নিজস্ব Alarm Tool → RIZERS in-app alarm system এ set
  // (phone এর native alarm app না, RIZERS এর নিজের feature)
} else if (response.action === "add_note") {
  // RIZERS Smart Notes Tool → Supabase notes table এ insert
} else if (response.action === "unclear") {
  // UI তে popup: "বুঝতে পারিনি, আবার বলুন" + reason দেখাও
}

// Confidence check (optional layer):
// যদি response এ একাধিক সম্ভাবনা থাকে বা field missing থাকে
// → UI তে "Confirm করুন" popup দেখাও, সরাসরি execute না করে
```

---

## ✅ Testing Checklist (Launch এর আগে)

- [ ] ১০+ ভিন্ন voice tone/accent দিয়ে test (দ্রুত বলা, ধীরে বলা)
- [ ] সময়ের বিভিন্ন বলার ধরন test ("সাড়ে ৬টা", "৬টা বাজে", "সন্ধ্যা ৬টা")
- [ ] Multiple todo + একসাথে alarm এর mixed command test
- [ ] Unclear/vague command এ ঠিকভাবে "unclear" ফেরত আসছে কিনা
- [ ] STT (Whisper) ভুল বুঝলে llama কীভাবে react করে সেটাও দেখা

---

*By Tayef | Rizers*
