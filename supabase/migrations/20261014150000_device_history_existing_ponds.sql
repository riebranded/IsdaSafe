-- Device location history lists only ponds that still exist: stays at a
-- deleted pond (or rebuilt from readings whose pond was already gone) are
-- left out of the history, the device list and the readings. Their rows and
-- readings are kept.

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
      select s.id, s.pond_id, p.name, true,
             s.user_id = (select auth.uid()),
             s.latitude, s.longitude, s.started_at, s.ended_at,
             public.device_stay_complete_count(s) as reading_count
        from public.device_locations s
        join public.ponds p on p.id = s.pond_id
       where s.device_id = upper(p_device_id)
         and public.can_view_device_history(p_device_id)
    ) stays
   where stays.reading_count > 0
   order by stays.started_at desc;
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
    join public.ponds p on p.id = s.pond_id
   where s.device_id in (
           select d.id from public.devices d where d.user_id = (select auth.uid())
           union
           select m.device_id from public.device_locations m where m.user_id = (select auth.uid()))
     and public.device_stay_complete_count(s) > 0
   group by s.device_id
   order by max(s.started_at) desc;
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
    join public.ponds p on p.id = s.pond_id
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
