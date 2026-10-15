-- Devices tab: a pond's complete readings from one device, averaged per day,
-- week, month or year (the timeframe picker's Daily / Weekly / Monthly /
-- Yearly). One row per period, dated by its start in the caller's time zone
-- (p_utc_offset_minutes); weeks start on Monday. Runs as the caller, so row
-- level security keeps it to the signed-in account's own readings.

create or replace function public.device_pond_readings_average(
  p_device_id text,
  p_pond_id uuid,
  p_step text,
  p_from timestamptz,
  p_to timestamptz,
  p_offset integer default 0,
  p_limit integer default 20,
  p_utc_offset_minutes integer default 0
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
security invoker
set search_path = ''
as $$
  select (date_trunc(p_step, r.created_at + make_interval(mins => p_utc_offset_minutes))
          - make_interval(mins => p_utc_offset_minutes))::timestamptz,
         avg(r.dissolved_oxygen)::real, avg(r.ph)::real, avg(r.ammonia)::real,
         avg(r.water_temperature)::real, avg(r.air_temperature)::real,
         avg(r.humidity)::real
    from public.sensor_readings r
   where r.device_id = p_device_id
     and r.pond_id = p_pond_id
     and p_step in ('day', 'week', 'month', 'year')
     and public.sensor_reading_is_complete(r)
     and r.created_at >= p_from
     and r.created_at <= p_to
   group by 1
   order by 1 desc
   offset greatest(p_offset, 0)
   limit least(greatest(p_limit, 1), 200);
$$;

revoke all on function public.device_pond_readings_average(text, uuid, text, timestamptz, timestamptz, integer, integer, integer) from public, anon;
grant execute on function public.device_pond_readings_average(text, uuid, text, timestamptz, timestamptz, integer, integer, integer) to authenticated;
