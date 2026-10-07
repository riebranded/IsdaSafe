-- "Needs photos": when the satellite check sees buildings over the pinned spot
-- it can't tell whether a pond is hidden there, so the owner is asked for at
-- least 3 photos of the pond, which verify-pond compares with the satellite
-- image. Adds that status and where the photos' paths/hashes are kept.

alter table public.ponds drop constraint if exists ponds_verification_status_check;
alter table public.ponds add constraint ponds_verification_status_check
  check (verification_status in ('pending', 'verified', 'rejected', 'error', 'needs_photos'));

alter table public.ponds
  add column if not exists evidence_photo_paths text[] not null default '{}',
  add column if not exists evidence_photo_hashes text[] not null default '{}';

-- Same rule as the other verification columns: only the edge function (service
-- role) writes them; a signed-in client can't edit or pre-fill them.
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
      new.verification_started_at := null;
      new.photo_hash := null;
      new.evidence_photo_paths := '{}';
      new.evidence_photo_hashes := '{}';
      if new.verification_method is null then
        new.verification_method := 'satellite';
      end if;
    else
      new.verification_status := old.verification_status;
      new.verification_message := old.verification_message;
      new.verification_confidence := old.verification_confidence;
      new.verification_started_at := old.verification_started_at;
      new.verification_method := old.verification_method;
      new.photo_path := old.photo_path;
      new.photo_hash := old.photo_hash;
      new.evidence_photo_paths := old.evidence_photo_paths;
      new.evidence_photo_hashes := old.evidence_photo_hashes;
    end if;
  end if;
  return new;
end;
$$;
