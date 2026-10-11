-- 1. A device monitors exactly one pond.
--    pair_device() now takes the pond and refuses a device that's already
--    paired with a different pond, whether that pond is this account's
--    ('in_use', with the pond's name) or another account's ('taken'). The owner
--    must remove it from that pond first (unpair_device). Pairing a device
--    again to the SAME pond is allowed (e.g. after reflashing its firmware) and
--    issues a new token.
--
-- 2. Changing a verified pond's location sends it back through verification.
--    The ponds_protect_verification trigger resets the verification fields
--    whenever a client changes the coordinates; the app then calls verify-pond
--    as it does for a new pond. Until it's verified again, the pond is off the
--    dashboard (its device keeps uploading readings).

drop function if exists public.pair_device(text);

-- Returns one of:
--   {"status": "paired", "token": "<64 hex>"}
--   {"status": "taken"}                        another account owns the device
--   {"status": "in_use", "pond_name": "..."}   paired with another of your ponds
--   {"status": "pond_has_device"}              this pond already has a device
create or replace function public.pair_device(p_device_id text, p_pond_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_id text := upper(p_device_id);
  v_device devices%rowtype;
  v_token text;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;
  if v_id !~ '^[0-9A-F]{12}$' then
    raise exception 'invalid device id';
  end if;
  if not exists (select 1 from ponds where id = p_pond_id and user_id = v_uid) then
    raise exception 'pond not found';
  end if;

  select * into v_device from devices where id = v_id for update;
  if found then
    if v_device.user_id <> v_uid then
      return jsonb_build_object('status', 'taken');
    end if;
    if v_device.pond_id is not null and v_device.pond_id <> p_pond_id then
      return jsonb_build_object(
        'status', 'in_use',
        'pond_name', (select name from ponds where id = v_device.pond_id)
      );
    end if;
  end if;

  if exists (select 1 from devices where pond_id = p_pond_id and id <> v_id) then
    return jsonb_build_object('status', 'pond_has_device');
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into devices (id, user_id, pond_id, token_hash)
  values (v_id, v_uid, p_pond_id, encode(extensions.digest(v_token, 'sha256'), 'hex'))
  on conflict (id) do update
    set token_hash = excluded.token_hash,
        pond_id = excluded.pond_id,
        paired_at = now();
  return jsonb_build_object('status', 'paired', 'token', v_token);
end;
$$;

revoke all on function public.pair_device(text, uuid) from public, anon;
grant execute on function public.pair_device(text, uuid) to authenticated;

-- One device per pond, enforced (pair_device checks it first to give a clear
-- answer).
create unique index if not exists devices_one_per_pond
  on public.devices (pond_id) where pond_id is not null;

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

      -- New location: the old verification no longer applies.
      if new.latitude is distinct from old.latitude
         or new.longitude is distinct from old.longitude then
        if old.verification_status = 'pending' then
          raise exception 'This pond is being verified. Change its location once that finishes.';
        end if;
        new.verification_status := 'pending';
        new.verification_message := null;
        new.verification_confidence := null;
        new.verification_started_at := null;
        -- Photos compared against the old spot's satellite view don't count
        -- for the new one. (In-house ponds are checked on their photos alone,
        -- which still apply.)
        if old.verification_method is distinct from 'photo' then
          new.evidence_photo_paths := '{}';
          new.evidence_photo_hashes := '{}';
        end if;
      end if;
    end if;
  end if;
  return new;
end;
$$;
