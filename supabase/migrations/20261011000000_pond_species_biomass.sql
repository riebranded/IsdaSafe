-- Biomass (total fish weight, kg) per species in a pond, asked when the owner
-- picks the pond's species, e.g. {"Tilapia": 120, "Milkfish": 45.5}. Sent to
-- the feeding-recommendation function so the feeding amount is worked out
-- from the actual stock.
alter table public.ponds
  add column if not exists species_biomass_kg jsonb not null default '{}'::jsonb;

alter table public.ponds
  drop constraint if exists ponds_species_biomass_kg_object;
alter table public.ponds
  add constraint ponds_species_biomass_kg_object
  check (jsonb_typeof(species_biomass_kg) = 'object');
