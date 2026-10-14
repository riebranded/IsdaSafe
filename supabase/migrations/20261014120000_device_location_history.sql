-- Location history for devices: every pond (and spot) a device has been filed
-- under, so its owner can look back at where it was and at the readings it
-- took there.
--
-- One row per stay: the device, the account it belonged to, the pond, and the
-- pond's name and coordinates at the time, from started_at until ended_at
-- (null while it's still there). A stay covers the readings
-- started_at <= created_at < ended_at sent by that device for that account.
--
-- Rows are written only by triggers, so every way a device moves is covered:
--   - devices: pair / claim / assign (pond set), unpair (row deleted),
--     transfer (owner changes, pond cleared), pond deleted (pond_id set null);
--   - ponds: the pond's location changed, so the device is somewhere new even
--     though its pond is the same.
-- The pond's name and coordinates are copied in, so a stay still shows where
-- it was after the pond is moved or deleted.

create table if not exists public.device_locations (
  id          bigint generated always as identity primary key,
  device_id   text not null,
  user_id     uuid not null references auth.users (id) on delete cascade,
  pond_id     uuid references public.ponds (id) on delete set null,
  pond_name   text,
  latitude    double precision,
  longitude   double precision,
  started_at  timestamptz not null default now(),
  ended_at    timestamptz
);
create index if not exists device_locations_user_device_idx
  on public.device_locations (user_id, device_id, started_at desc);
create index if not exists device_locations_pond_idx
  on public.device_locations (pond_id) where pond_id is not null;
-- A device is in one place at a time.
create unique index if not exists device_locations_one_open
  on public.device_locations (device_id) where ended_at is null;

alter table public.device_locations enable row level security;
revoke insert, update, delete on public.device_locations from anon, authenticated;
create policy "device locations: owner can read"
  on public.device_locations for select to authenticated
  using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

create or replace function public.devices_track_location()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Leaving: removed, moved to another pond, or handed to another account.
  if tg_op = 'DELETE'
     or (tg_op = 'UPDATE' and (new.pond_id is distinct from old.pond_id
                               or new.user_id is distinct from old.user_id)) then
    update public.device_locations
       set ended_at = now()
     where device_id = old.id and ended_at is null;
  end if;

  -- Arriving at a pond.
  if tg_op <> 'DELETE' and new.pond_id is not null
     and (tg_op = 'INSERT'
          or new.pond_id is distinct from old.pond_id
          or new.user_id is distinct from old.user_id) then
    insert into public.device_locations (device_id, user_id, pond_id, pond_name, latitude, longitude)
    select new.id, new.user_id, p.id, p.name, p.latitude, p.longitude
      from public.ponds p
     where p.id = new.pond_id;
  end if;

  return null;
end;
$$;

drop trigger if exists devices_track_location on public.devices;
create trigger devices_track_location
  after insert or delete or update of pond_id, user_id on public.devices
  for each row execute function public.devices_track_location();

-- A pond moved: its device's stay at the old spot ends and one at the new
-- spot begins.
create or replace function public.ponds_track_device_location()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.latitude is distinct from old.latitude
     or new.longitude is distinct from old.longitude then
    with closed as (
      update public.device_locations
         set ended_at = now()
       where pond_id = new.id and ended_at is null
      returning device_id, user_id
    )
    insert into public.device_locations (device_id, user_id, pond_id, pond_name, latitude, longitude)
    select c.device_id, c.user_id, new.id, new.name, new.latitude, new.longitude
      from closed c;
  end if;
  return null;
end;
$$;

drop trigger if exists ponds_track_device_location on public.ponds;
create trigger ponds_track_device_location
  after update of latitude, longitude on public.ponds
  for each row execute function public.ponds_track_device_location();

revoke execute on function public.devices_track_location() from public, anon, authenticated;
revoke execute on function public.ponds_track_device_location() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Reading it back
-- ---------------------------------------------------------------------------

-- The signed-in account's stays for one device, newest first, each with how
-- many readings it took there. pond_name is the pond's current name while the
-- pond exists (pond_exists), otherwise the name it had.
create or replace function public.device_location_history(p_device_id text)
returns table (
  id            bigint,
  pond_id       uuid,
  pond_name     text,
  pond_exists   boolean,
  latitude      double precision,
  longitude     double precision,
  started_at    timestamptz,
  ended_at      timestamptz,
  reading_count bigint
)
language sql
stable
set search_path = ''
as $$
  select s.id, s.pond_id, coalesce(p.name, s.pond_name), p.id is not null,
         s.latitude, s.longitude, s.started_at, s.ended_at,
         (select count(*) from public.sensor_readings r
           where r.device_id = s.device_id
             and r.user_id = s.user_id
             and r.created_at >= s.started_at
             and (s.ended_at is null or r.created_at < s.ended_at))
    from public.device_locations s
    left join public.ponds p on p.id = s.pond_id
   where s.device_id = upper(p_device_id)
     and s.user_id = (select auth.uid())
   order by s.started_at desc;
$$;

revoke execute on function public.device_location_history(text) from public, anon;
grant execute on function public.device_location_history(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Backfill from readings already uploaded
-- ---------------------------------------------------------------------------

-- Each unbroken run of a device's readings under one account and pond is a
-- stay. It lasts until the device's next run starts (or just past its last
-- reading). Coordinates are the pond's current ones: where it was before
-- this table existed isn't recorded anywhere.
insert into public.device_locations (device_id, user_id, pond_id, pond_name, latitude, longitude, started_at, ended_at)
select i.device_id, i.user_id, p.id, p.name, p.latitude, p.longitude, i.first_at,
       coalesce(lead(i.first_at) over (partition by i.device_id order by i.first_at),
                i.last_at + interval '1 millisecond')
  from (
    select device_id, user_id, pond_id, min(created_at) as first_at, max(created_at) as last_at
      from (
        select device_id, user_id, pond_id, created_at,
               row_number() over (partition by device_id order by created_at)
             - row_number() over (partition by device_id, user_id, pond_id order by created_at) as run
          from public.sensor_readings
         where device_id is not null and user_id is not null
      ) runs
     group by device_id, user_id, pond_id, run
  ) i
  left join public.ponds p on p.id = i.pond_id
 where not exists (select 1 from public.device_locations);

-- Devices sitting on a pond right now: their latest run is still going on,
-- or, if they have no readings there yet, their stay began when paired.
update public.device_locations s
   set ended_at = null
  from public.devices d
 where d.pond_id is not null
   and s.device_id = d.id and s.user_id = d.user_id and s.pond_id = d.pond_id
   and s.started_at = (select max(started_at) from public.device_locations x where x.device_id = d.id)
   and not exists (select 1 from public.device_locations o where o.device_id = d.id and o.ended_at is null);

insert into public.device_locations (device_id, user_id, pond_id, pond_name, latitude, longitude, started_at)
select d.id, d.user_id, p.id, p.name, p.latitude, p.longitude, d.paired_at
  from public.devices d
  join public.ponds p on p.id = d.pond_id
 where not exists (select 1 from public.device_locations o where o.device_id = d.id and o.ended_at is null);
