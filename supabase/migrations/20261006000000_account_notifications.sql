-- Account-change notifications (phone / email / password success or failure).
-- Written by the app itself right after the change attempt, so authenticated
-- users may insert — but only their own rows, and only `account_*` types (the
-- pond verification notifications stay server-only).
create policy "notifications: owner can add account events"
  on public.notifications for insert to authenticated
  with check (user_id = auth.uid() and type like 'account\_%' and pond_id is null);
