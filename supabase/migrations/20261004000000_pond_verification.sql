-- Pond verification: how each pond was verified when added, the in-house
-- photo (if any), and a log used to rate-limit the verify-pond edge function
-- (every call costs a Google Static Maps request + a vision-model request).

alter table public.ponds
  add column if not exists verification_method text
    check (verification_method in ('satellite', 'photo')),
  add column if not exists verification_confidence real,
  add column if not exists photo_path text,
  add column if not exists photo_hash text;

-- A given photo can back only one pond (checked in verify-pond, enforced here).
create unique index if not exists ponds_photo_hash_key
  on public.ponds (photo_hash) where photo_hash is not null;

create table if not exists public.pond_verification_log (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  mode text not null check (mode in ('satellite', 'photo')),
  created_at timestamptz not null default now()
);
create index if not exists pond_verification_log_user_created_idx
  on public.pond_verification_log (user_id, created_at desc);
-- RLS on with no policies: only the edge function (service role) touches it.
alter table public.pond_verification_log enable row level security;

-- Private bucket for in-house pond photos; each user can only touch their own
-- folder (<uid>/<file>).
insert into storage.buckets (id, name, public)
values ('pond-photos', 'pond-photos', false)
on conflict (id) do nothing;

create policy "pond photos: owner can upload"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'pond-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "pond photos: owner can read"
  on storage.objects for select to authenticated
  using (bucket_id = 'pond-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "pond photos: owner can delete"
  on storage.objects for delete to authenticated
  using (bucket_id = 'pond-photos' and (storage.foldername(name))[1] = auth.uid()::text);
