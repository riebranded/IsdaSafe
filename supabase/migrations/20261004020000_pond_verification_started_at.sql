-- Lets verify-pond tell "a check is running right now" from "pending but never
-- started / stuck", so a retry can't start a second run on top of the first.

alter table public.ponds add column if not exists verification_started_at timestamptz;

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
    end if;
  end if;
  return new;
end;
$$;
