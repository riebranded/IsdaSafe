-- "Send a test SMS alert" (Settings): each test text, so the send-test-sms
-- edge function can cap them (they cost Semaphore credits). Server-only.
create table if not exists public.test_sms_log (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  status     text not null,
  created_at timestamptz not null default now()
);
create index if not exists test_sms_log_user_idx on public.test_sms_log (user_id, created_at desc);
alter table public.test_sms_log enable row level security;
revoke all on public.test_sms_log from anon, authenticated;
