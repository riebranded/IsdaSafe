-- QR-code claiming, alongside USB pairing. (Already applied to the live
-- project as migration 20261009111614 "device_qr_claim"; saved here so the
-- repo matches it.)
--
-- Each device is provisioned when it's flashed (tools/provision_device.py):
--   - a random 64-hex secret, written into the device, which it sends with
--     every reading (ingest_sensor_reading() accepts it once the device is
--     claimed);
--   - a claim code, printed with the device ID on the device's QR label.
-- register_device_credentials() stores only their hashes. Scanning the label
-- in the app calls claim_device(): the claim code proves the user holds the
-- device, and the device is filed under their account (and pond). A device
-- that already belongs to someone else can only be transferred with its
-- owner's approval (request_device_transfer() / respond_device_transfer()).
-- Claim attempts are rate-limited per user.

create table public.device_credentials (
  id               text primary key check (id ~ '^[0-9A-F]{12}$'),
  secret_hash      text not null unique,
  claim_code_hash  text not null,
  created_at       timestamptz not null default now()
);
alter table public.device_credentials enable row level security;
revoke all on public.device_credentials from anon, authenticated;

create table public.device_claim_log (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  device_id   text not null,
  created_at  timestamptz not null default now()
);
create index device_claim_log_user_time_idx on public.device_claim_log (user_id, created_at desc);
alter table public.device_claim_log enable row level security;
revoke all on public.device_claim_log from anon, authenticated;

create table public.device_transfer_requests (
  id            uuid primary key default gen_random_uuid(),
  device_id     text not null,
  requester_id  uuid not null references auth.users (id) on delete cascade,
  owner_id      uuid not null references auth.users (id) on delete cascade,
  status        text not null default 'pending'
                check (status in ('pending', 'approved', 'declined', 'cancelled')),
  created_at    timestamptz not null default now(),
  resolved_at   timestamptz
);
create unique index device_transfer_requests_one_pending_idx
  on public.device_transfer_requests (device_id, requester_id) where status = 'pending';
create index device_transfer_requests_owner_idx
  on public.device_transfer_requests (owner_id, status);
alter table public.device_transfer_requests enable row level security;
revoke insert, update, delete on public.device_transfer_requests from anon, authenticated;

create policy "device transfer requests: owner or requester can read"
  on public.device_transfer_requests for select
  to authenticated
  using (owner_id = (select auth.uid()) or requester_id = (select auth.uid()));

create function public.normalize_claim_code(p_code text)
returns text language sql immutable set search_path = '' as $$
  select upper(regexp_replace(coalesce(p_code, ''), '[^0-9A-Za-z]', '', 'g'));
$$;

create function public.device_claim_code_ok(p_device_id text, p_code text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.device_credentials c
    where c.id = upper(p_device_id)
      and c.claim_code_hash = extensions.crypt(public.normalize_claim_code(p_code), c.claim_code_hash)
  );
$$;
revoke execute on function public.device_claim_code_ok(text, text) from public, anon, authenticated;

create function public.device_claim_rate_limited(p_device_id text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_recent int;
begin
  select count(*) into v_recent from public.device_claim_log
  where user_id = auth.uid() and created_at > now() - interval '1 hour';
  insert into public.device_claim_log (user_id, device_id) values (auth.uid(), upper(coalesce(p_device_id, '')));
  return v_recent >= 10;
end;
$$;
revoke execute on function public.device_claim_rate_limited(text) from public, anon, authenticated;

create function public.register_device_credentials(p_device_id text, p_secret text, p_claim_code text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_id   text := upper(p_device_id);
  v_code text := public.normalize_claim_code(p_claim_code);
begin
  if v_id !~ '^[0-9A-F]{12}$' then raise exception 'invalid device id'; end if;
  if p_secret !~ '^[0-9a-f]{64}$' then raise exception 'secret must be 64 lowercase hex chars'; end if;
  if length(v_code) < 8 then raise exception 'claim code too short'; end if;

  insert into public.device_credentials (id, secret_hash, claim_code_hash)
  values (v_id,
          encode(extensions.digest(p_secret, 'sha256'), 'hex'),
          extensions.crypt(v_code, extensions.gen_salt('bf')))
  on conflict (id) do update
    set secret_hash = excluded.secret_hash,
        claim_code_hash = excluded.claim_code_hash,
        created_at = now();
end;
$$;
revoke execute on function public.register_device_credentials(text, text, text) from public, anon, authenticated;
grant execute on function public.register_device_credentials(text, text, text) to service_role;

create function public.claim_device(p_device_id text, p_claim_code text, p_pond_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid    uuid := auth.uid();
  v_id     text := upper(coalesce(p_device_id, ''));
  v_cred   public.device_credentials%rowtype;
  v_device public.devices%rowtype;
begin
  if v_uid is null then raise exception 'not signed in'; end if;
  if public.device_claim_rate_limited(v_id) then
    return jsonb_build_object('status', 'rate_limited');
  end if;
  if not public.device_claim_code_ok(v_id, p_claim_code) then
    return jsonb_build_object('status', 'invalid');
  end if;
  if p_pond_id is not null
     and not exists (select 1 from public.ponds where id = p_pond_id and user_id = v_uid) then
    raise exception 'pond not found';
  end if;

  select * into v_device from public.devices where id = v_id for update;
  if found then
    if v_device.user_id = v_uid then
      return jsonb_build_object(
        'status', 'already_yours',
        'device_id', v_id,
        'pond_id', v_device.pond_id,
        'pond_name', (select name from public.ponds where id = v_device.pond_id));
    end if;
    return jsonb_build_object(
      'status', 'owned_by_other',
      'device_id', v_id,
      'transfer_pending', exists (
        select 1 from public.device_transfer_requests
        where device_id = v_id and requester_id = v_uid and status = 'pending'));
  end if;

  if p_pond_id is not null
     and exists (select 1 from public.devices where pond_id = p_pond_id) then
    return jsonb_build_object('status', 'pond_has_device');
  end if;

  select * into v_cred from public.device_credentials where id = v_id;
  insert into public.devices (id, user_id, pond_id, token_hash)
  values (v_id, v_uid, p_pond_id, v_cred.secret_hash)
  on conflict (id) do nothing;
  if not found then
    return jsonb_build_object('status', 'owned_by_other', 'device_id', v_id, 'transfer_pending', false);
  end if;
  return jsonb_build_object('status', 'claimed', 'device_id', v_id, 'pond_id', p_pond_id);
end;
$$;
revoke execute on function public.claim_device(text, text, uuid) from public, anon;
grant execute on function public.claim_device(text, text, uuid) to authenticated;

create function public.request_device_transfer(p_device_id text, p_claim_code text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid    uuid := auth.uid();
  v_id     text := upper(coalesce(p_device_id, ''));
  v_owner  uuid;
  v_pond   uuid;
  v_name   text;
begin
  if v_uid is null then raise exception 'not signed in'; end if;
  if public.device_claim_rate_limited(v_id) then
    return jsonb_build_object('status', 'rate_limited');
  end if;
  if not public.device_claim_code_ok(v_id, p_claim_code) then
    return jsonb_build_object('status', 'invalid');
  end if;

  select user_id, pond_id into v_owner, v_pond from public.devices where id = v_id;
  if not found then return jsonb_build_object('status', 'unclaimed'); end if;
  if v_owner = v_uid then return jsonb_build_object('status', 'already_yours'); end if;

  insert into public.device_transfer_requests (device_id, requester_id, owner_id)
  values (v_id, v_uid, v_owner)
  on conflict (device_id, requester_id) where status = 'pending' do nothing;
  if not found then return jsonb_build_object('status', 'already_requested'); end if;

  select nullif(trim(full_name), '') into v_name from public.profiles where id = v_uid;
  insert into public.notifications (user_id, pond_id, type, title, body)
  values (v_owner, v_pond, 'device_transfer_request',
          'Device transfer requested',
          coalesce(v_name, 'Another IsdaSafe user') || ' scanned your device ' || v_id ||
          ' and asked for it to be transferred to their account. Approve only if you gave them this device.');
  return jsonb_build_object('status', 'requested');
end;
$$;
revoke execute on function public.request_device_transfer(text, text) from public, anon;
grant execute on function public.request_device_transfer(text, text) to authenticated;

create function public.respond_device_transfer(p_request_id uuid, p_approve boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_req public.device_transfer_requests%rowtype;
begin
  if v_uid is null then raise exception 'not signed in'; end if;

  select * into v_req from public.device_transfer_requests
  where id = p_request_id and owner_id = v_uid and status = 'pending'
  for update;
  if not found then raise exception 'transfer request not found'; end if;

  if not p_approve then
    update public.device_transfer_requests set status = 'declined', resolved_at = now() where id = v_req.id;
    insert into public.notifications (user_id, type, title, body)
    values (v_req.requester_id, 'device_transfer_result', 'Device transfer declined',
            'The owner of device ' || v_req.device_id || ' declined your transfer request.');
    return jsonb_build_object('status', 'declined');
  end if;

  update public.devices
     set user_id = v_req.requester_id, pond_id = null, paired_at = now()
   where id = v_req.device_id and user_id = v_uid;
  if not found then
    update public.device_transfer_requests set status = 'cancelled', resolved_at = now() where id = v_req.id;
    return jsonb_build_object('status', 'no_longer_owner');
  end if;

  update public.device_transfer_requests set status = 'approved', resolved_at = now() where id = v_req.id;
  update public.device_transfer_requests set status = 'cancelled', resolved_at = now()
   where device_id = v_req.device_id and status = 'pending';
  insert into public.notifications (user_id, type, title, body)
  values (v_req.requester_id, 'device_transfer_result', 'Device transferred to you',
          'Device ' || v_req.device_id || ' is now yours. Open it in the app to choose its pond.');
  return jsonb_build_object('status', 'approved', 'device_id', v_req.device_id);
end;
$$;
revoke execute on function public.respond_device_transfer(uuid, boolean) from public, anon;
grant execute on function public.respond_device_transfer(uuid, boolean) to authenticated;

create or replace function public.ingest_sensor_reading(
  p_token text,
  p_dissolved_oxygen real default null, p_ph real default null, p_ammonia real default null,
  p_water_temperature real default null, p_air_temperature real default null, p_humidity real default null)
returns text language plpgsql security definer set search_path to 'public' as $function$
declare
  v_hash   text := encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');
  v_device devices%rowtype;
begin
  select * into v_device from devices where token_hash = v_hash;
  if not found then
    select d.* into v_device
      from devices d join device_credentials c on c.id = d.id
     where c.secret_hash = v_hash;
  end if;
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
$function$;
