-- Cold-start personalization: persist the "তুমি কী করো?" (profession) answer already
-- collected at signup step 3 (lpData.prof, js/app.js's lpPick / index.html's duplicate) but
-- previously discarded — never sent in the signUp()/profiles.upsert() calls. Used only as a
-- small, low-confidence category-affinity seed inside _rzGetUserSignals() (js/app.js) for a
-- user's first sessions, before real watch/reaction/save history exists. No trigger needed —
-- not in profile_completion_score's field list or profiles_protect_sensitive_columns_trg's
-- guarded-column list, so the existing profiles_update_own RLS policy already covers a plain
-- user-writes-own-row update.
alter table profiles add column if not exists signup_profession text;
