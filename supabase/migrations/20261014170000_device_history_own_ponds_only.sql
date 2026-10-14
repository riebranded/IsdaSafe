-- Device location history shows only the signed-in account's own ponds:
-- stays under other accounts (the device's earlier or later owners) are no
-- longer listed, and their readings can't be opened. Still only ponds that
-- exist and stays with at least one complete reading.

create or replace function public.device_location_history(p_device_id text)
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
      select s.id, s.pond_id, p.name, true, true,
             s.latitude, s.longitude, s.started_at, s.ended_at,
             public.device_stay_complete_count(s) as reading_count
        from public.device_locations s
        join public.ponds p on p.id = s.pond_id and p.user_id = s.user_id
       where s.device_id = upper(p_device_id)
         and s.user_id = (select auth.uid())
    ) stays
   where stays.reading_count > 0
   order by stays.started_at desc;
$$;

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
    join public.ponds p on p.id = s.pond_id and p.user_id = s.user_id
    join public.sensor_readings r
      on r.device_id = s.device_id
     and r.user_id = s.user_id
     and r.created_at >= s.started_at
     and (s.ended_at is null or r.created_at < s.ended_at)
   where s.id = p_stay_id
     and s.user_id = (select auth.uid())
     and public.sensor_reading_is_complete(r)
   order by r.created_at desc
   offset greatest(p_offset, 0)
   limit least(greatest(p_limit, 1), 200);
$$;

create or replace function public.device_history_devices()
returns setof text
language sql
stable
security definer
set search_path = ''
as $$
  select s.device_id
    from public.device_locations s
    join public.ponds p on p.id = s.pond_id and p.user_id = s.user_id
   where s.user_id = (select auth.uid())
     and public.device_stay_complete_count(s) > 0
   group by s.device_id
   order by max(s.started_at) desc;
$$;
