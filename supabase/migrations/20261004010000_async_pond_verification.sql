-- Asynchronous pond verification: ponds are saved as 'pending', the verify-pond
-- edge function verifies them in the background, then records the outcome,
-- creates an in-app notification and sends an SMS.

alter table public.ponds
  add column if not exists verification_status text not null default 'verified'
    check (verification_status in ('pending', 'verified', 'rejected', 'error')),
  add column if not exists verification_message text;
-- Existing ponds predate verification and stay 'verified' (the column default).

-- Only the edge function (service role) may decide verification results. A
-- signed-in client can't insert a pond as 'verified' or edit the outcome later.
create or replace function public.ponds_protect_verification()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if auth.role() in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      new.verification_status := 'pending';
      new.verification_message := null;
      new.verification_confidence := null;
      new.photo_hash := null;
      if new.verification_method is null then
        new.verification_method := 'satellite';
      end if;
    else
      new.verification_status := old.verification_status;
      new.verification_message := old.verification_message;
      new.verification_confidence := old.verification_confidence;
      new.verification_method := old.verification_method;
      new.photo_path := old.photo_path;
      new.photo_hash := old.photo_hash;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists ponds_protect_verification on public.ponds;
create trigger ponds_protect_verification
  before insert or update on public.ponds
  for each row execute function public.ponds_protect_verification();

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  pond_id uuid references public.ponds (id) on delete set null,
  type text not null,
  title text not null,
  body text not null,
  sms_status text check (sms_status in ('sent', 'failed', 'skipped')),
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user_created_idx
  on public.notifications (user_id, created_at desc);

alter table public.notifications enable row level security;

-- Created only by the edge function (service role bypasses RLS); users can
-- read their own, mark them read, and dismiss them.
create policy "notifications: owner can read"
  on public.notifications for select to authenticated
  using (user_id = auth.uid());
create policy "notifications: owner can mark read"
  on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "notifications: owner can delete"
  on public.notifications for delete to authenticated
  using (user_id = auth.uid());

-- Live updates in the app.
alter publication supabase_realtime add table public.notifications;
