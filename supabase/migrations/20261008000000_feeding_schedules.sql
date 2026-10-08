-- One AI feeding schedule per pond + species + language per day. The app reads
-- today's row first and only asks the model when there isn't one, so the
-- schedule is generated once a day (from the sensor readings at that moment,
-- kept in `readings` for reference).
create table if not exists public.feeding_schedules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  pond_id uuid not null references public.ponds (id) on delete cascade,
  species text not null,
  language text not null default 'en',
  schedule_date date not null,
  feeding_time text not null,
  feeding_frequency text not null,
  feeding_amount text not null,
  water_quality_recommendations jsonb not null default '[]'::jsonb,
  possible_risks jsonb not null default '[]'::jsonb,
  -- Sensor readings the schedule was generated from, e.g.
  -- {"temperature": 27.4, "ph": 7.1, "dissolved_oxygen": 6.2, "ammonia": 0.05}
  readings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (pond_id, species, language, schedule_date)
);

create index if not exists feeding_schedules_user_date_idx
  on public.feeding_schedules (user_id, schedule_date desc);

alter table public.feeding_schedules enable row level security;

create policy "feeding schedules: owner can read"
  on public.feeding_schedules for select to authenticated
  using (user_id = auth.uid());

create policy "feeding schedules: owner can add"
  on public.feeding_schedules for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.ponds p
      where p.id = pond_id and p.user_id = auth.uid()
    )
  );

create policy "feeding schedules: owner can update"
  on public.feeding_schedules for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "feeding schedules: owner can delete"
  on public.feeding_schedules for delete to authenticated
  using (user_id = auth.uid());
