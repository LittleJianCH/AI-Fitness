# Canonical Data and Import/Export Policy

**Read when:** changing canonical units/time, source handling, Bike authority, or import/export semantics.

| Concern | Required behavior |
| --- | --- |
| Units and time | Use explicit canonical units and unambiguous instants. Keep timezone context when local dates matter. Distinguish elapsed/moving duration and missing/zero values. |
| Original files | Files may be retained separately to support later re-parsing. Do not require domain operations to merge raw sources or reparse every file on every read. Retention lifetime and future fields must not be invented by the agent. |
| Derived data | Record the calculation/parser version when persisted derived results require reproducibility or invalidation; do not introduce a general event-sourcing system. |
| Removed merging | No multi-device stream fusion or workout-combination feature. Retry deduplication/idempotency is not the same feature as semantic merging. |
| Bike authority | User-maintained Bike data is authoritative. FIT metadata cannot unconditionally overwrite it. |
| Import/export policy | Support category-specific ignore/adopt choices. Export may include user-maintained Bike information when selected and representable in the target FIT format. |
| Coordinates | Canonical coordinates use WGS84. Convert identified non-WGS84 sources at the boundary using device/settings policy; do not guess or transform the same coordinates twice. |
| AI-generated data | Validate drafts like other external inputs. Preserve uncertainty and missing data instead of inventing measurements or presenting estimates as direct observations. |
