# Feeding Schedule ML Pipeline — Implementation Plan

This is a design doc, not shipped code — it lays out how to go from today's
mock sensor data to a trained regression model that recommends a feeding
schedule (amount + frequency) per pond. Species suitability stays on the
existing rule-based `SuggestionEngine` (see decision log at the bottom); this
pipeline is scoped to feeding schedule only.

## Current state (as of writing)

- `MockSensorService` (`lib/services/mock_sensor_service.dart`) generates all
  readings from a seeded random walk. **There is no real historical sensor or
  feeding data anywhere in this project.**
- The only backend is Supabase — used today for auth (`docs/AUTH_SETUP.md`)
  and one edge function (`supabase/functions/verify-firebase-phone`). No
  tables exist yet for sensor history or feeding outcomes.
- `metricBands` (`lib/models/reading_bands.dart`) and `FishSpeciesCatalog`
  (`lib/services/fish_species_catalog.dart`) encode expert-defined ranges —
  these are the only "ground truth" available right now, and they describe
  *water-quality suitability*, not feeding amount/frequency.

Because of this, the plan runs in two phases: bootstrap on synthetic data to
get the pipeline shape working end-to-end, then swap in real data once it
exists, without changing the pipeline's shape.

---

## Phase 0 — Data collection (prerequisite for Phase 2)

Add two Supabase tables so real data starts accumulating immediately,
independent of when the model work happens:

**`sensor_readings`**
| column | type | notes |
|---|---|---|
| `id` | uuid pk | |
| `pond_id` | uuid fk | |
| `metric_type` | text | mirrors `MetricType` enum (`temperature`, `humidity`, `ammonia`, `dissolvedOxygen`, `ph`) |
| `value` | double | |
| `recorded_at` | timestamptz | |

**`feeding_events`**
| column | type | notes |
|---|---|---|
| `id` | uuid pk | |
| `pond_id` | uuid fk | |
| `species` | text | matches `FishSpecies.name` |
| `amount_grams` | double | actual amount fed |
| `fed_at` | timestamptz | |
| `outcome_notes` | text, nullable | optional: mortality, growth observation, leftover feed — whatever the farmer logs |

Wire the real device/sensor ingestion path to write to `sensor_readings`
instead of (or alongside) `MockSensorService`, and add a lightweight
"log feeding" action in the app that writes to `feeding_events`. This table
pair is the label source for Phase 2 — the sooner it starts filling, the
sooner real training is possible. This can proceed independently of
Phases 1 and 3.

---

## Phase 1 — Bootstrap dataset (synthetic, for pipeline development only)

Generate synthetic (readings → target) pairs from the existing expert rules
so the pipeline has *something* to train and validate against before real
data exists. This teaches the pipeline shape, not real fish behavior — do not
ship a model trained only on this phase.

Synthesis approach:
1. Sample readings uniformly across each metric's `_Band` in
   `MockSensorService` (temp 20–34°C, DO 1–9 mg/L, pH 5.5–9.5, ammonia
   0–0.3 mg/L).
2. For each sample + each species in `FishSpeciesCatalog`, derive a synthetic
   feeding-amount target using a hand-written heuristic (e.g. base ration
   scaled by how centered the readings are in that species' optimal range
   from `metricBands`/`FishSpecies` ranges, tapering toward zero outside the
   `MatchVerdict.unsuitable` boundary). This is a stand-in label function,
   documented clearly as synthetic in code comments.
3. Add Gaussian noise to the target to avoid the model trivially learning the
   exact heuristic formula.

Output: a CSV/Parquet file, one row per (pond reading snapshot, species),
columns = features below + `target_amount_grams`.

---

## Feature schema (shared by both phases)

| feature | source | notes |
|---|---|---|
| `temperature`, `ph`, `dissolved_oxygen`, `ammonia` | `sensor_readings` / `SensorReading.value` | raw values |
| `species_temp_mid`, `species_ph_mid`, `species_do_mid`, `species_ammonia_mid` | `FishSpecies` ranges | midpoint of each species' optimal range — lets one model serve all species without one-hot species explosion |
| `species_name` | `FishSpecies.name` | categorical, one-hot or target-encoded |
| `pond_age_days` | derived | days since pond/stocking start, if tracked |
| `hour_of_day` | derived from `recorded_at` | feeding rate is time-of-day dependent |
| *(Phase 2 only, if trend matters)* `temp_delta_24h`, `do_delta_24h` | rolling window over `sensor_readings` | only add if point-in-time regression underperforms — see the earlier discussion in this thread |

`humidity` is deliberately excluded — same reasoning as `SuggestionEngine`:
it's ambient air humidity, not a driver of aquatic feeding behavior.

---

## Phase 2 — Model

- **Baseline**: gradient-boosted trees (XGBoost or LightGBM) regressing on
  `target_amount_grams` (and optionally a second small model or multi-output
  head for feeding frequency/times-per-day). Chosen over a CNN — no
  spatial structure in this feature set — and over a deep MLP initially,
  since tree ensembles handle small tabular datasets with mixed
  numeric/categorical features well without heavy tuning.
- **Train/val split**: group by `pond_id` (not random row split) so the
  model isn't validated on readings from a pond it already saw — otherwise
  validation score is optimistic.
- **Metrics**: MAE and RMSE on `amount_grams`; sanity-check predictions
  against the `metricBands` critical thresholds (a pond in `criticalLow` DO
  should predict near-zero feed, not a normal ration — starving fish don't
  feed).
- **Escalation path**: only move to an MLP/temporal model (LSTM over a
  reading window) if trend-dependent features (Phase 2 feature table, last
  row) prove necessary and tree models plateau.

---

## Phase 3 — Serving

Options, in order of how much new infra they need:

1. **Supabase Edge Function** wrapping the trained model (via ONNX runtime
   or a small Python service) — mirrors the existing
   `verify-firebase-phone` pattern already in this repo. Flutter calls the
   function, gets back `{amount_grams, times_per_day, next_feed_at}`.
2. **On-device** via `tflite_flutter` if latency/offline support matters more
   than easy retraining — convert the trained model to TFLite.

Recommendation: start with (1) — it fits the existing Supabase-function
pattern in this repo and keeps retraining/redeployment simple.

---

## Decision log (context from prior discussion)

- **Species suitability stays rule-based** (`SuggestionEngine`) — it's a
  narrow, well-defined range-lookup problem; an LLM or trained model adds
  hallucination/drift risk without a clear benefit over the existing
  deterministic, explainable ranges.
- **Feeding schedule is the ML/LLM candidate** — it's a more open-ended
  synthesis problem (amount × frequency × trend), where a learned model or
  LLM reasoning has more to add than a lookup table does.
- **LLM vs trained model for feeding schedule**: this doc covers the trained
  regression path. An LLM-based approach (Claude via structured outputs) was
  discussed as a no-training-data-required alternative — worth prototyping
  in parallel since Phase 0 data collection will take time regardless.

## Open questions to resolve before Phase 2 starts

- [ ] Is pond stocking/species assignment tracked anywhere yet (needed for
      `species_name` and `pond_age_days` features)?
- [ ] Who logs `feeding_events` in practice — the farmer via the app, or an
      automated feeder device? Affects how reliably Phase 0 data arrives.
- [ ] Minimum viable dataset size before attempting Phase 2 on real data —
      suggest revisiting once `feeding_events` has a few hundred rows across
      multiple ponds.
