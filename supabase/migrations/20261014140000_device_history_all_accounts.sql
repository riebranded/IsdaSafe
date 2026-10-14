-- Device location history across accounts: a device's history shows every
-- pond it was paired to, whichever account owned it at the time, with each
-- stay's location and complete readings.
--
-- Who can see it: anyone who owns the device now or owned it before (has a
-- stay of their own with it). They see the previous and later owners' pond
-- names, locations and readings for that device.
--
-- Other accounts' ponds and readings are hidden from clients by row-level
-- security, so these functions are SECURITY DEFINER and check that access
-- themselves.

-- Whether the signed-in user owns or ever owned [p_device_id].
create or replace function public.can_view_device_history(p_device_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null and (
    exists (select 1 from public.devices d
             where d.id = upper(p_device_id) and d.user_id = (select auth.uid()))
    or exists (select 1 from public.device_locations s
                where s.device_id = upper(p_device_id) and s.user_id = (select auth.uid())));
$$;
revoke execute on function public.can_view_device_history(text) from public, anon, authenticated;

-- Complete readings a stay covers (the stay's device and account, inside its
-- time window).
create or replace function public.device_stay_complete_count(s public.device_locations)
returns bigint
language sql
stable
set search_path = ''
as $$
  select count(*) from public.sensor_readings r
   where r.device_id = s.device_id
     and r.user_id = s.user_id
     and r.created_at >= s.started_at
     and (s.ended_at is null or r.created_at < s.ended_at)
     and public.sensor_reading_is_complete(r);
$$;
revoke execute on function public.device_stay_complete_count(public.device_locations) from public, anon, authenticated;

-- Every stay of the device with complete readings, from all accounts, newest
-- first. is_mine marks the signed-in user's own stays.
drop function if exists public.device_location_history(text);
create function public.device_location_history(p_device_id text)
returns table (
  id            bigint,
  pond_id       uuid,
  pond_name     text,
  pond_exists   boolean,
  is_mine       boolean,
  latitude      double precision,
  longitude     double precision,
  started_at    timestamptz,
  ended_at      timestamptz,
  reading_count bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  select stays.*
    from (
      select s.id, s.pond_id, coalesce(p.name, s.pond_name), p.id is not null,
             s.user_id = (select auth.uid()),
             s.latitude, s.longitude, s.started_at, s.ended_at,
             public.device_stay_complete_count(s) as reading_count
        from public.device_locations s
        left join public.ponds p on p.id = s.pond_id
       where s.device_id = upper(p_device_id)
         and public.can_view_device_history(p_device_id)
    ) stays
   where stays.reading_count > 0
   order by stays.started_at desc;
$$;

-- Devices the signed-in user owns or owned that have at least one stay (by
-- any account) with complete readings, most recently placed first.
create or replace function public.device_history_devices()
returns setof text
language sql
stable
security definer
set search_path = ''
as $$
  select s.device_id
    from public.device_locations s
   where s.device_id in (
           select d.id from public.devices d where d.user_id = (select auth.uid())
           union
           select m.device_id from public.device_locations m where m.user_id = (select auth.uid()))
     and public.device_stay_complete_count(s) > 0
   group by s.device_id
   order by max(s.started_at) desc;
$$;

-- One page of a stay's complete readings, newest first.
create or replace function public.device_stay_readings(
  p_stay_id bigint,
  p_offset integer default 0,
  p_limit integer default 20
) returns table (
  created_at        timestamptz,
  dissolved_oxygen  real,
  ph                real,
  ammonia           real,
  water_temperature real,
  air_temperature   real,
  humidity          real
)
language sql
stable
security definer
set search_path = ''
as $$
  select r.created_at, r.dissolved_oxygen, r.ph, r.ammonia,
         r.water_temperature, r.air_temperature, r.humidity
    from public.device_locations s
    join public.sensor_readings r
      on r.device_id = s.device_id
     and r.user_id = s.user_id
     and r.created_at >= s.started_at
     and (s.ended_at is null or r.created_at < s.ended_at)
   where s.id = p_stay_id
     and public.can_view_device_history(s.device_id)
     and public.sensor_reading_is_complete(r)
   order by r.created_at desc
   offset greatest(p_offset, 0)
   limit least(greatest(p_limit, 1), 200);
$$;

revoke execute on function public.device_location_history(text) from public, anon;
grant execute on function public.device_location_history(text) to authenticated;
revoke execute on function public.device_history_devices() from public, anon;
grant execute on function public.device_history_devices() to authenticated;
revoke execute on function public.device_stay_readings(bigint, integer, integer) from public, anon;
grant execute on function public.device_stay_readings(bigint, integer, integer) to authenticated;
