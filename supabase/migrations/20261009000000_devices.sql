-- IsdaSafe hardware devices and who owns them.
--
-- Ownership is proven by a secret token, not by the device ID (the ESP32's
-- chip ID, which isn't secret). Pairing happens over USB in the app:
--   1. pair_device() registers the device to the signed-in account and
--      returns a fresh random token, storing only its SHA-256 hash.
--   2. The app writes the token into the device over USB (`PAIR <token>`);
--      the firmware keeps it in flash.
--   3. The device sends the token with every reading to
--      ingest_sensor_reading(), which files the reading under the token's
--      account and pond. Nothing in the request body can choose the account.
-- A device owned by one account can't be paired by another until the owner
-- removes it (unpair_device), which also revokes its token.

create table if not exists public.devices (
  id text primary key check (id ~ '^[0-9A-F]{12}$'),
  user_id uuid not null references auth.users (id) on delete cascade,
  pond_id uuid references public.ponds (id) on delete set null,
  token_hash text not null unique,
  paired_at timestamptz not null default now()
);
create index if not exists devices_user_idx on public.devices (user_id);
create index if not exists devices_pond_idx on public.devices (pond_id);

-- Owners can see their devices; every change goes through the functions
-- below.
alter table public.devices enable row level security;
create policy "devices: owner can read"
  on public.devices for select to authenticated
  using (user_id = auth.uid());

-- Returns {"status": "paired", "token": "<64 hex>"} or {"status": "taken"}.
-- Re-pairing a device you already own issues a new token (the old one stops
-- working), e.g. after reflashing the firmware.
create or replace function public.pair_device(p_device_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_id text := upper(p_device_id);
  v_owner uuid;
  v_token text;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;
  if v_id !~ '^[0-9A-F]{12}$' then
    raise exception 'invalid device id';
  end if;

  select user_id into v_owner from devices where id = v_id for update;
  if v_owner is not null and v_owner <> v_uid then
    return jsonb_build_object('status', 'taken');
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into devices (id, user_id, token_hash)
  values (v_id, v_uid, encode(extensions.digest(v_token, 'sha256'), 'hex'))
  on conflict (id) do update
    set token_hash = excluded.token_hash,
        paired_at = now();
  return jsonb_build_object('status', 'paired', 'token', v_token);
end;
$$;

-- Files the device's future readings under one of the owner's ponds.
create or replace function public.assign_device_pond(
  p_device_id text,
  p_pond_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from ponds where id = p_pond_id and user_id = auth.uid()
  ) then
    raise exception 'pond not found';
  end if;
  update devices set pond_id = p_pond_id
  where id = upper(p_device_id) and user_id = auth.uid();
  if not found then
    raise exception 'device not found';
  end if;
end;
$$;

-- Releases the device (revoking its token) so it can be paired again, by
-- this or another account. Its past readings stay with this account.
create or replace function public.unpair_device(p_device_id text)
returns void
language sql
security definer
set search_path = public
as $$
  delete from devices
  where id = upper(p_device_id) and user_id = auth.uid();
$$;

revoke all on function public.pair_device(text) from public, anon;
revoke all on function public.assign_device_pond(text, uuid) from public, anon;
revoke all on function public.unpair_device(text) from public, anon;
grant execute on function public.pair_device(text) to authenticated;
grant execute on function public.assign_device_pond(text, uuid) to authenticated;
grant execute on function public.unpair_device(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Readings: owned by the account of the device that sent them.
-- ---------------------------------------------------------------------------

alter table public.sensor_readings
  add column if not exists user_id uuid references auth.users (id) on delete cascade,
  add column if not exists pond_id uuid references public.ponds (id) on delete set null;
create index if not exists sensor_readings_user_time_idx
  on public.sensor_readings (user_id, created_at desc);
create index if not exists sensor_readings_pond_time_idx
  on public.sensor_readings (pond_id, created_at desc);

-- Previously anyone could insert a reading for any device_id, and every
-- signed-in user could read every reading.
drop policy if exists "devices can insert readings" on public.sensor_readings;
drop policy if exists "authenticated can read readings" on public.sensor_readings;

create policy "sensor readings: owner can read"
  on public.sensor_readings for select to authenticated
  using (user_id = auth.uid());

-- The only way to add a reading. Called by the device (anon key) with its
-- pairing token; null values are sensors that failed to read.
create or replace function public.ingest_sensor_reading(
  p_token text,
  p_dissolved_oxygen real default null,
  p_ph real default null,
  p_ammonia real default null,
  p_water_temperature real default null,
  p_air_temperature real default null,
  p_humidity real default null
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_device devices%rowtype;
begin
  select * into v_device from devices
  where token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');
  if not found then
    raise exception 'device not paired' using errcode = '28000';
  end if;

  insert into sensor_readings (
    device_id, user_id, pond_id,
    dissolved_oxygen, ph, ammonia, water_temperature, air_temperature, humidity
  ) values (
    v_device.id, v_device.user_id, v_device.pond_id,
    p_dissolved_oxygen, p_ph, p_ammonia, p_water_temperature, p_air_temperature, p_humidity
  );
  return 'ok';
end;
$$;

revoke all on function public.ingest_sensor_reading(text, real, real, real, real, real, real) from public;
grant execute on function public.ingest_sensor_reading(text, real, real, real, real, real, real) to anon, authenticated;
