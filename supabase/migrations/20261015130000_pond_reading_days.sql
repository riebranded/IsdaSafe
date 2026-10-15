-- Custom timeframes only allow days a pond has readings: the days (in the
-- caller's time zone, given as its UTC offset) with at least one reading in
-- the last two years, newest first. p_device_id limits it to one device's
-- readings and p_complete_only to complete ones (the Devices tab). Runs as
-- the caller, so row level security keeps it to the account's own readings.

create or replace function public.pond_reading_days(
  p_pond_id uuid,
  p_device_id text default null,
  p_complete_only boolean default false,
  p_utc_offset_minutes integer default 0
) returns table (day date)
language sql
stable
security invoker
set search_path = ''
as $$
  select distinct (r.created_at + make_interval(mins => coalesce(p_utc_offset_minutes, 0)))::date as d
    from public.sensor_readings r
   where r.pond_id = p_pond_id
     and r.created_at >= now() - interval '2 years 2 days'
     and (p_device_id is null or r.device_id = p_device_id)
     and (not p_complete_only or public.sensor_reading_is_complete(r))
   order by d desc;
$$;

revoke all on function public.pond_reading_days(uuid, text, boolean, integer) from public, anon;
grant execute on function public.pond_reading_days(uuid, text, boolean, integer) to authenticated;
