-- Trend charts: a pond's readings between two times, grouped into equal
-- steps (15 minutes, hour, day, week, month or year, in Philippine time),
-- with each metric's average, lowest and highest per step. Lets the app chart
-- a week, a month or a year without downloading every reading.
--
-- One row per step and metric. Free ammonia is worked out per reading with
-- free_ammonia(), like the app does. Runs as the caller, so the
-- "owner can read" policy on sensor_readings still applies.
create or replace function public.pond_reading_trend(
  p_pond_id uuid,
  p_start timestamptz,
  p_end timestamptz,
  p_step text
)
returns table (
  bucket timestamptz,
  metric text,
  readings bigint,
  avg_value real,
  min_value real,
  max_value real
)
language plpgsql
stable
security invoker
set search_path = public
as $$
begin
  if p_step not in ('15min', 'hour', 'day', 'week', 'month', 'year') then
    raise exception 'unknown step %', p_step using errcode = '22023';
  end if;

  return query
  with src as (
    select
      case p_step
        when '15min' then date_bin(
          interval '15 minutes', r.created_at, timestamptz '2000-01-01 00:00+08')
        else date_trunc(p_step, r.created_at, 'Asia/Manila')
      end as step_start,
      r.dissolved_oxygen, r.ph, r.ammonia, r.water_temperature,
      r.air_temperature, r.humidity,
      free_ammonia(r.ammonia, r.ph, r.water_temperature) as free_nh3
    from sensor_readings r
    where r.pond_id = p_pond_id
      and r.created_at >= p_start
      and r.created_at <= p_end
  )
  select
    src.step_start,
    m.metric,
    count(m.v),
    avg(m.v)::real,
    min(m.v)::real,
    max(m.v)::real
  from src
  cross join lateral (values
    ('dissolved_oxygen', src.dissolved_oxygen),
    ('ph', src.ph),
    ('ammonia', src.ammonia),
    ('water_temperature', src.water_temperature),
    ('air_temperature', src.air_temperature),
    ('humidity', src.humidity),
    ('free_ammonia', src.free_nh3)
  ) as m(metric, v)
  where m.v is not null
  group by src.step_start, m.metric
  order by src.step_start;
end;
$$;

revoke execute on function public.pond_reading_trend(uuid, timestamptz, timestamptz, text)
  from public, anon;
grant execute on function public.pond_reading_trend(uuid, timestamptz, timestamptz, text)
  to authenticated;
