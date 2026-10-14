-- Device location history shows only the places a device actually measured:
-- a stay is listed only when the device sent at least one complete reading
-- there (every sensor reported a value), and reading_count counts only those.
-- Devices without any such stay aren't listed at all.

create or replace function public.sensor_reading_is_complete(r public.sensor_readings)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select r.dissolved_oxygen is not null and r.ph is not null
     and r.ammonia is not null and r.water_temperature is not null
     and r.air_temperature is not null and r.humidity is not null;
$$;

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
  select *
    from (
      select s.id, s.pond_id, coalesce(p.name, s.pond_name), p.id is not null,
             s.latitude, s.longitude, s.started_at, s.ended_at,
             (select count(*) from public.sensor_readings r
               where r.device_id = s.device_id
                 and r.user_id = s.user_id
                 and r.created_at >= s.started_at
                 and (s.ended_at is null or r.created_at < s.ended_at)
                 and public.sensor_reading_is_complete(r)) as reading_count
        from public.device_locations s
        left join public.ponds p on p.id = s.pond_id
       where s.device_id = upper(p_device_id)
         and s.user_id = (select auth.uid())
    ) stays
   where stays.reading_count > 0
   order by stays.started_at desc;
$$;

-- The signed-in account's devices that have at least one such stay, most
-- recently placed first.
create or replace function public.device_history_devices()
returns setof text
language sql
stable
set search_path = ''
as $$
  select s.device_id
    from public.device_locations s
   where s.user_id = (select auth.uid())
     and exists (
       select 1 from public.sensor_readings r
        where r.device_id = s.device_id
          and r.user_id = s.user_id
          and r.created_at >= s.started_at
          and (s.ended_at is null or r.created_at < s.ended_at)
          and public.sensor_reading_is_complete(r))
   group by s.device_id
   order by max(s.started_at) desc;
$$;

revoke execute on function public.device_location_history(text) from public, anon;
grant execute on function public.device_location_history(text) to authenticated;
revoke execute on function public.device_history_devices() from public, anon;
grant execute on function public.device_history_devices() to authenticated;
