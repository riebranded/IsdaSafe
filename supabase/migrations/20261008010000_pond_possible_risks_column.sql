-- Possible risks get their own column; water_advice now holds only the
-- water-quality recommendations. Both refresh every 15 minutes.
--   water_advice:   { "<lang>": { "<species>": { water_quality_recommendations: [], generated_at } } }
--   possible_risks: { "<lang>": { "<species>": { possible_risks: [], generated_at } } }
alter table public.ponds
  add column if not exists possible_risks jsonb not null default '{}'::jsonb;
