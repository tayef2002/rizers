-- Run in Supabase SQL editor.
-- Manual bKash subscription flow (per user's choice: no automated Payment
-- Gateway API yet — "manual system thakbe, pore api connect korbo"). The user
-- submits a Transaction ID after sending money by hand; verification means
-- checking the actual bKash account and flipping status to 'approved' here
-- in the Supabase table editor. Approving auto-activates the subscription via
-- the trigger below — that one status flip is the only manual step needed.

create table if not exists subscription_payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id),
  plan text not null default 'monthly',
  amount numeric not null,
  trx_id text not null,
  status text not null default 'pending', -- pending | approved | rejected
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);

alter table subscription_payments enable row level security;

drop policy if exists "select own subscription payments" on subscription_payments;
create policy "select own subscription payments" on subscription_payments
  for select using (auth.uid() = user_id);

drop policy if exists "insert own subscription payments" on subscription_payments;
create policy "insert own subscription payments" on subscription_payments
  for insert with check (auth.uid() = user_id);

-- No update/delete policy for regular users on purpose — only the project
-- owner can change status, via the Supabase table editor (which uses the
-- service role and bypasses RLS). Users can submit and view their own
-- claims, never approve their own payment.

alter table profiles add column if not exists subscription_status text not null default 'trial';
alter table profiles add column if not exists subscription_expires_at timestamptz;

create or replace function sp_activate_on_approval()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    new.reviewed_at = now();
    update profiles
      set subscription_status = 'active',
          -- Renewing an already-active subscription extends from its current
          -- expiry; renewing a lapsed/new one starts counting from today.
          subscription_expires_at = greatest(coalesce(subscription_expires_at, now()), now())
            + (case when new.plan = '10day' then interval '10 days' else interval '30 days' end)
      where id = new.user_id;
  end if;
  return new;
end;
$$;

drop trigger if exists sp_activate_on_approval_trg on subscription_payments;
create trigger sp_activate_on_approval_trg
  before update on subscription_payments
  for each row
  execute function sp_activate_on_approval();
