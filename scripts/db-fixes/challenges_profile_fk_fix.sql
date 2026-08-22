-- Run in Supabase SQL editor.
-- challenges.creator_id and challenge_participants.user_id were created as FKs to auth.users(id),
-- which is correct for RLS (auth.uid() comparisons still work identically either way, since
-- profiles.id is always equal to the matching auth.users.id) but doesn't give PostgREST a
-- discoverable relationship for embedding profile data (select('*, profiles(name)')) the way
-- posts.user_id already does elsewhere in this app — confirmed live: querying
-- challenges.select('*, profiles(name)') returned PGRST200 "Could not find a relationship
-- between 'challenges' and 'profiles' in the schema cache". Repointing both FKs at profiles(id)
-- instead fixes the embed without touching any RLS policy or existing data.

alter table challenges drop constraint if exists challenges_creator_id_fkey;
alter table challenges add constraint challenges_creator_id_fkey foreign key (creator_id) references profiles(id) on delete cascade;

alter table challenge_participants drop constraint if exists challenge_participants_user_id_fkey;
alter table challenge_participants add constraint challenge_participants_user_id_fkey foreign key (user_id) references profiles(id) on delete cascade;
