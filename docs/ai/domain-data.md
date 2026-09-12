# Canonical Data and Import/Export Policy

**Read when:** changing canonical units/time, source handling, Bike authority, or import/export semantics.

| Concern | Required behavior |
| --- | --- |
| Units and time | Use explicit canonical units and unambiguous instants. Keep timezone context when local dates matter. Distinguish elapsed/moving duration and missing/zero values. |
| Original FIT files | Successful FIT inputs are archived by default until user deletion or explicit cleanup, as defined by the current backend architecture. Ordinary reads and analysis use canonical data rather than reparsing the archive. Raw retention supports explicit reprocessing/backfill; it is not a backup of later user edits. |
| Derived data | Record the calculation/parser version when persisted derived results require reproducibility or invalidation; do not introduce a general event-sourcing system. |
| No cross-source fusion | Do not fuse sensor streams across devices/sources or automatically infer/merge independent workouts. Retry deduplication/idempotency is not semantic merging. `WorkoutGroup` is allowed to associate otherwise independent Workouts, including multiple parts explicitly represented by one source; grouping does not combine their identities or observation streams. |
| Bike authority | User-maintained Bike data is authoritative. FIT metadata cannot unconditionally overwrite it. |
| Import/export policy | Support category-specific ignore/adopt choices. Export may include user-maintained Bike information when selected and representable in the target FIT format. |
| Coordinates | Canonical coordinates use WGS84. Convert identified non-WGS84 sources at the boundary using device/settings policy; do not guess or transform the same coordinates twice. |
| AI-generated data | Validate drafts like other external inputs. Preserve uncertainty and missing data instead of inventing measurements or presenting estimates as direct observations. |

When import/group behavior is involved, consult the relevant current sections of `docs/backend-architecture.md`; do not infer semantics from older snapshots.
