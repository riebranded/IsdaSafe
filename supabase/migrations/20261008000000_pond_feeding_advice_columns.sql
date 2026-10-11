-- Feeding advice lives on the pond row (no separate table).
drop table if exists public.feeding_schedules;

-- Per-language, per-species AI feeding schedule; regenerated once a day.
--   { "<lang>": { "<species>": { feeding_time, feeding_frequency, feeding_amount,
--                                generated_at, readings } } }
alter table public.ponds
  add column if not exists feeding_schedules jsonb not null default '{}'::jsonb;

-- Per-language, per-species water-quality recommendations and risks; refreshed
-- every 15 minutes.
--   { "<lang>": { "<species>": { water_quality_recommendations: [],
--                                generated_at } } }
alter table public.ponds
  add column if not exists water_advice jsonb not null default '{}'::jsonb;
