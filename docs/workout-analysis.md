# Workout detail analysis

## Reference and delivery scope

The design reference is an interactive inspection of HealthFit on 2026-09-19:
cycling with power/cadence and outdoor running with power/running dynamics.
No personal observations, routes or screenshots are stored as fixtures.

The detail experience combines a route, metric overview, typed statistics,
distance splits, source laps and dedicated metric analysis pages. Cycling adds
power distribution, duration curve and cadence analysis. Running adds pace,
power and running dynamics. Analytical results are owned by Haskell; clients own
formatting, chart selection, navigation and map interaction.

Recorded summaries remain distinct from recomputed measurements. Missing inputs
are not zero, timer duration is not moving duration, and a sampling gap is not a
recorded pause. Every analysis response identifies its workout revision, algorithm
and coverage policy. Client identity/revision checks protect concurrent refreshes.

These are versioned AI Fitness calculations, not a claim of numerical equivalence
with HealthFit's undisclosed algorithms.

## Shared client behavior

The Web, iOS and Android implementations share this information order: route and
recorded overview; sensor metrics; cycling power or running dynamics; heart-rate
load; distance splits and source laps; recorded source/context. Training history
is reachable from the load section. Settings group software preferences, body
parameter history, equipment and account/session controls.

Desktop and mobile layouts may differ. The Web retains its existing visual
language; SwiftUI and Jetpack Compose use native mobile controls and navigation.
All clients consume the same server projections and preserve their unavailable,
partial-coverage and revision states. They do not reimplement load, normalized
power, distribution, split or fatigue calculations.

Client verification must connect to a disposable real backend, including settings
save/reload and workout analysis. Mock and contract tests complement those checks;
they do not replace them. Runtime-specific verification and any unavailable
device/toolchain are reported separately.

## Calculation definitions

`GET /api/v1/workouts/{id}/analysis` reads one owner-scoped workout and its settings
in the same authenticated transaction, then calculates outside the account lock.
The response identifies the workout revision, settings revision and selected body
profile. It never changes observations or recorded summaries.

* Sensor statistics/histograms integrate linear segments at most 120 seconds
  apart. Extrema use observed values. A singleton has no duration-weighted mean.
  Excluding zero removes zero plateaus, not isolated zero endpoints. Histograms
  widen their nominal bin width to remain at most 64 bins. Gap comparisons allow
  at most four machine epsilons at the elapsed timestamp magnitude, capped at one
  nanosecond, for conversion/subtraction rounding at exact boundaries.
* Power uses five-second gaps. Normalized power integrates complete 30-second
  rolling windows at one-second endpoints, averages fourth powers, then takes
  the fourth root. Gaps reset windows and startup padding is not invented.
  Complete-second endpoints use the same capped conversion-scale tolerance, so
  a fractional start time does not lose the final complete rolling window.
  The fourth moment is scaled by contributing windows; isolated observations,
  short disconnected runs and fractional tails cannot change that scale.
  The returned normalization duration
  counts one-second rolling endpoints; seven days of supported power is the
  processing limit.
* Variability is normalized/mean power; intensity is normalized power/FTP.
  Stress is `IF² * elapsed_seconds / 36` and needs full power coverage. Work is
  observed watts integrated into joules; W/kg requires mass. Efficiency is
  normalized power/mean HR with full common coverage. Decoupling compares this
  efficiency in equal elapsed halves of at least 30 seconds. Sensor and power
  statistics include pauses, unlike the HRSS timer rules below.
* One- and five-kilometre splits require a nondecreasing distance stream without
  gaps over 120 seconds. They interpolate distance crossings, start at the first
  observed distance, retain a partial final segment and include elapsed stops.
  No distance is invented from GPS. Each set is bounded to 2,000 splits.
  Half comparisons use equal distance; source laps remain separate.
* Running steps require full cadence coverage. Flight time is
  `60 / steps_per_minute - contact_seconds` when nonnegative. Vertical ratio is
  oscillation/step length. Flight ratio is flight/(flight+contact). Running
  effectiveness needs full speed/power coverage and mass. Derived flight/ratio
  means use linear segments between the combined breakpoints of both contributing
  sensor clocks, intersecting supported intervals without bridging gaps.
* Relationships align sensor timestamps without extrapolation across gaps.
  Correlation uses all aligned pairs and is sample-based; constant signals have
  no coefficient. At most 600 points are rendered.

References: [TrainingPeaks normalized power](https://help.trainingpeaks.com/hc/en-us/articles/204071804-Normalized-Power)
and [efficiency/decoupling](https://help.trainingpeaks.com/hc/en-us/articles/204071724-Aerobic-Decoupling-Pw-Hr-and-Pa-HR-and-Efficiency-Factor-EF).
Short or non-steady efforts require careful interpretation. These displays do not
classify physiological readiness or health risk.

## Settings and parameter history

`GET/PUT /api/v1/settings` is scoped to the authenticated owner. PUT carries the
expected decimal-string revision and the server increments it. Account locking
serializes both creation and updates; stale writes return 409, invalid documents
422. Collection limits are checked before entry/history validation. Migration
`1789776000-user-settings.sql` adds a versioned JSONB document.

Software preferences control system/light/dark appearance; display units remain
metric. Body profiles contain an immutable UUID, effective UTC start, optional
mass/height, and separate cycling/running FTP and heart-rate parameters. The
history is append-only, ordered, and bounded to 1,000 entries. Selection uses the
workout's start. Choosing a past effective time intentionally affects workouts
after that time; the form explains this. Existing entries cannot be rewritten.
Imported workout mass/FTP take precedence over profile fallback values. Profiles
are never extrapolated backward.

Heart-rate settings require `0 < resting < threshold <= maximum` and explicit
1.92 or 1.67 exponential weighting, never inferred from identity. Equipment supports
bicycles/shoes, optional mass, renaming and retirement, bounded to 200 entries.
Identity and kind cannot be removed. Catalog edits do not rewrite workout context.

## Heart-rate load and fitness history

The existing pure `Analysis.HeartRate` and `Analysis.Fatigue` engine is integrated
with the settings/API boundaries. HRSS left-holds readings for at most ten seconds
and integrates over recorded active timer intervals. It does not hold a final
sample to workout end or reuse a pre-pause reading after resume. Missing timers
use a labelled elapsed-time fallback. Above-maximum HR is excluded and reduces
coverage; below-resting HR contributes zero. Availability requires 95% coverage.
Partial observed scores are not scaled to fill missing time and are labelled.

HRSS normalizes against one hour at threshold. TRIMPexp integrates
`minutes * reserve * 0.64 * exp(k * reserve)`, using the selected exponent, following
the [time-integrated TRIMP formulation](https://pmc.ncbi.nlm.nih.gov/articles/PMC6561225/).
HR zones use reserve boundaries 50/60/70/80/90%, with separate below-50% and
at/above-maximum bands. Power zones use FTP boundaries 55/75/90/105/120/150%.

`POST /api/v1/analysis/training-history` accepts 1–366 consecutive civil days,
each with a date label, UTC bounds and explicit recording completeness. iOS's
timezone-aware Gregorian calendar supplies real daylight-saving boundaries.
The backend validates contiguous intervals, consecutive dates, day lengths, and
each boundary's UTC-12 through UTC+14 displacement from its labelled midnight;
it does not infer an IANA timezone from an offset. These are
analysis inputs, not changes to workout timestamps. History admits at most 1,000
owner-filtered workouts and 128 MiB of expanded observation/user-data JSON. It
selects IDs first, measures bytes, then bulk-loads the admitted records under the
same account lock. Oversized requests fail entirely with `analysis_too_large`;
clients should offer a smaller calendar instead of silently truncating history.
A workout belongs to its local start date across midnight.

The byte guard bounds input size, not decoded heap or query duration. A local
synthetic probe decoding eight dense eight-hour rides (about 64.4 MiB JSON) and
calculating history used about 1.47 GiB of total GHC runtime memory. PostgreSQL's
expanded-size calculation also performs work while holding the account lock.
These are current processing limits, not a memory/concurrency guarantee.

The request explicitly chooses zero prior load or supplies both prior CTL and
ATL in the same HRSS scale. Confirmed complete empty days are rest; unconfirmed
days are unknown. Missing HR parameters or inadequate coverage make a day's total
unknown and propagate unknown through subsequent CTL/ATL. Excluded workouts and
zero-active-time workouts contribute known zero. CTL/ATL decay factors are
`exp(-1/42)` and `exp(-1/7)`. The response reports the initial state's remaining
CTL weight. No alternative power or pace load is substituted.

## Presentation and verification

The iOS Settings tab contains software settings, body history, equipment and
account/session controls. Metric cards link to time/distance plots, synchronized
comparison panels, distributions and scatter plots. Rendering is bounded; raw
samples and full-stream gap identities are preserved. Routes offer start/end
markers, full-screen standard/satellite views and breaks at gaps over 120 seconds.
Running dynamics, source laps, altitude/energy summaries and bicycle context are
shown with missing-data states.

Tests cover pure numerical/coverage rules, profile dates, revisions, owner
isolation, concurrent writes, unknown/rest history, DST, cancelled/late responses
and session changes. HTTP checks use disposable PostgreSQL. iOS integration uses
synthetic records in a dedicated simulator; inspected personal HealthFit data is
never copied into fixtures or uploaded.

HealthFit's post-workout recovery readings, grade-adjusted pace, GPS-accuracy
analysis, similar-workout ranking, tiles and Eddington views are not represented
by this implementation. Post-workout readings need an explicit model outside the
canonical workout sample interval. The equipment catalog manages equipment but
does not assign shoes or replace existing recorded bicycle context.
