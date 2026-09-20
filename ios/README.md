# AI Fitness for iOS

The native client uses SwiftUI and the shared Servant-generated Swift API client.
It implements native login, Keychain-backed session restoration, server-confirmed
logout, backend workout browsing, explicit HealthKit-to-backend import, and
user-confirmed backend-to-HealthKit export with durable recovery and receipts.

The Settings tab groups appearance, effective-dated body/training parameters,
bicycle/shoe management and account controls. Workout details include backend
statistics, metric analysis, distance splits, power/heart-rate zones, running
dynamics, fitness-history analysis and full-screen routes. Raw metric charts,
metric navigation/comparison, and the separately requested power curve remain
available when derived workout analysis fails; retry applies to the derived
analysis. Settings requests and cached values are isolated by session identity,
including account changes during a save. Account changes hide the previous
settings immediately; same-account refresh keeps the current appearance and
parameters visible until replacement values arrive. Training-history requests use each
civil day's actual boundaries, including midnight daylight-saving changes. See
[the analysis definitions](../docs/workout-analysis.md) for coverage policies,
parameter precedence, algorithm assumptions and explicit remaining feature gaps.

## Build

The minimum baseline is Xcode 15.4, Swift 5.10, and iOS 17 or later. Select Xcode
with its platform SDKs installed. The macOS core test package requires macOS 14.
The Xcode project is maintained in `Fitness.xcodeproj`; its `FitnessCore` product
comes from this directory's local Swift package. `App/FitnessApp.swift` owns the
app entry point; `ServerScreen.swift` owns server selection, and
`AuthenticatedRoot.swift` owns the session and signed-in tabs. These views are
explicit members of the app target. Generated contracts are build
inputs, not checked-in Swift sources.

Generate the contract using the root development environment:

```sh
nix develop -c make -C backend contract contract-test
nix develop -c bash -c 'cd contracts && node openapi.mjs'
cp contracts/build/openapi.json contracts/swift/Sources/ContractClient/openapi.json
```

Then open `ios/Fitness.xcodeproj`, select the `Fitness` scheme and an iOS simulator.
SPM may fetch the pinned packages on first use. The added Apple
`swift-openapi-urlsession` 1.0.2 package supplies HTTP transport for the existing
generator/runtime versions, rather than maintaining a second JSON client.
Keep both the package and Xcode workspace resolution locks.
The generator is pinned to 1.7.0: its upstream Foundation-import fixes are
required by newer Swift toolchains (including Xcode 27). The runtime and
transport pins are unchanged.

Keep Xcode's local simulator signing enabled: Keychain requires the app identity
in its signing entitlements. Disabling code signing may build successfully but
does not verify credential storage. Physical-device signing is configured separately.

From the repository root:

```sh
swift test --package-path ios --disable-automatic-resolution
xcodebuild -project ios/Fitness.xcodeproj -scheme Fitness \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath ios/DerivedData \
  -skipPackagePluginValidation build
```

## Connect and sign in

Enter the server origin, such as `https://fitness.example.com`, without `/api/v1`.
Debug builds additionally accept HTTP for loopback development, for example
`http://127.0.0.1:8000` in the simulator. Release builds require HTTPS. A physical
device needs a reachable HTTPS endpoint and its own signing configuration; the
backend currently binds to the Mac's loopback interface, so merely entering the
Mac's LAN address does not expose it.

Create an account through the existing browser registration API when registration
is temporarily enabled. Native registration is not part of the v1 contract.
The disposable integration harness below performs this bootstrap automatically
for its own test account only. It is not an account-provisioning tool for an
existing developer or production database.

Credentials are scoped to the server origin and stored in Keychain using
`WhenUnlockedThisDeviceOnly`. Passwords are cleared from the form when submitted.
On launch, `/me` verifies the saved credential. HTTP 401 clears it; network or
server failures preserve it and offer retry. Logout is only reported complete
after server revocation succeeds (or the server reports the session invalid).
An explicit local-forget action is available after restoration failure, and does
not claim to revoke the remote session.

Each identity change advances an in-memory generation. Responses from earlier
generations cannot publish the current user or clear a newer login. The network
session disables cookies and caching; native requests use only Bearer credentials.
Raw generated-client errors are never rendered or logged because they can include
request bodies. User-facing messages are selected from status/error categories.

## Isolated simulator integration

The workout tab loads owner-scoped backend summaries with cycling/running filters,
pull-to-refresh, and cursor pagination. Repeated identities across pages update
the row rather than duplicating it; a failed page can be retried. Filter changes
and session changes invalidate earlier responses. No workout data is cached on disk.

Details show the recorded summary separately from any backend-calculated summary,
user metadata, data-quality notes, a WGS84 route, and independent heart-rate,
power, speed, grade, ambient temperature, altitude and sport-specific cadence plots.
Grade remains signed percentage points and temperature remains Celsius. Display conversions use
kilometres and km/h; running cadence remains total steps/minute and average pace
uses min/km. Missing values remain visibly missing. Sample timestamps are retained;
chart lines are visual guides across samples, not additional measurements.
Chart lines use at most 600 samples; selection searches the full original stream
on the chosen time/distance axis and displays the actual sample timestamp.

Core tests consume the synthetic backend contract fixtures generated above. They
cover pagination retry/deduplication, late filter/session responses, cancellation,
detail retry and display-unit conversion alongside authentication checks.

```sh
nix develop -c bash scripts/ios_integration_test
```

The script creates a private PostgreSQL cluster with no TCP listener, migrates it,
starts the actual backend on a temporary loopback port, registers a synthetic
account with synthetic cycling/running records, and creates a dedicated iPhone 15 /
iOS 17.5 simulator. It runs the XCUITest login, wrong-password, workout list/filter/
detail, relaunch/restoration and logout scenarios. It also verifies body mass/height
and equipment name/mass after relaunch, persisted body mass/FTP in backend
analysis, metric comparison and axis switching, negative grade/temperature
analysis, and explicit training-history assumptions with unknown daily loads.
A failure/recovery case verifies raw metric and power-curve availability while
derived analysis is unavailable. The harness then removes the server, database and
simulator. A profile-fallback fixture starts one hour after test setup and omits
imported athlete parameters, so the newly effective profile can be tested without
changing real timestamps or depending on the current calendar date. Existing
`DATABASE_URL` values and devices are not used. Logs and Xcode results remain in ignored `ios/build` and `ios/DerivedData`.
The result bundle retains screenshots of settings editors, saved history, metric
comparison, distributions and training history for native UI review.
History capacity errors ask for a shorter date range. Unavailable calculations
are reported separately from connection failures; server diagnostics stay hidden.
Running the UI suite without the harness skips the real-backend scenario; that
skip is not evidence of successful integration.

The suite also checks the HealthKit import entry screen and exports a synthetic
running workout through the system Health access sheet. Its disposable simulator
contains no real health records. Simulator results are not evidence of
physical-device HealthKit behavior.

## Import from Apple Health

The Health tab requests read access when the user presses **Authorize and read**.
It examines up to 200 recent cycling/running workouts fully within the selected
date range, excluding this app's exported objects. Users select one or several
records, preview the available summary/sample counts/route, and explicitly confirm
upload to the currently signed-in backend. Changing the selection clears previews.
Empty results cannot distinguish read denial from missing data.

The first projection includes reported duration, distance/active energy, available
heart-rate/power/speed statistics, associated heart-rate/power/speed samples,
cycling cadence, running stride/vertical oscillation/ground contact time, distance
and active-energy increments, and routes/altitude with valid location accuracy.
Only the workout's own HealthKit source and fully contained associated quantity
samples are read. There is no cross-source fusion or inferred running cadence.
Interval measurements are placed at interval end. Non-overlapping distance/energy
increments form cumulative streams; available sample totals do not replace the
reported workout totals. Duplicate sample end-times and overlapping cumulative
increments reject the preview rather than choosing values or double-counting.
Invalid-accuracy route positions are omitted; altitude is absent when its accuracy
is invalid. The normalized data includes a projection note and source label.
Pause/resume events retain timer meaning; other events retain their numeric
HealthKit kind and interval end as descriptive events. Lap summaries, arbitrary
source-specific fields and multisport workouts are outside this initial projection.
The supported sample limit is 50,000 per preview and selection is limited to ten
workouts per batch to bound in-memory previews.

The reader owns HealthKit objects within each asynchronous operation outside the
UI actor. Only Sendable value snapshots cross into UI state. Workouts/previews are
kept in memory; no anchors or automatic background sync are introduced. HealthKit
read permission may be incomplete, and later associated data may arrive: reselect
and preview again before explicitly refreshing an existing import.

Uploads use the dedicated `/imports/healthkit` contract and source UUID, never a
manual workout creation request. Only a `succeeded` record with its matching source
and complete mapping is presented as confirmed. A normal repeat does not overwrite
observations. Failed unpublished inputs offer revision-checked retry; published
inputs offer explicit refresh with current workout revisions while preserving user
metadata. Suppression remains visible. Lost responses can safely repeat the normal
request; a batch stops on rate limiting and retains results for later retry.
Session changes/cancellation cannot publish a late acknowledgement into the new UI.

The Xcode target has the HealthKit entitlement and a read-purpose description.
Device verification requires a signing team/provisioning profile with HealthKit,
a reachable HTTPS backend, and test records the owner is willing to read/upload.
Verify per-type permission choices, empty/partial results, source association,
route access, cancellation, duplicate imports and explicit refresh on that device.
Simulator compilation and synthetic core/HTTP tests do not replace these checks.

Platform references: [associated samples](https://developer.apple.com/documentation/healthkit/hkquery/predicateforobjects(from:)-5irg9),
[workout route queries](https://developer.apple.com/documentation/healthkit/hkworkoutroutequery),
and [HealthKit queries](https://developer.apple.com/documentation/healthkit/queries).

## Export to Apple Health

Open a backend workout, choose **Export to Apple Health**, read the projection,
and confirm. The app requests only the write/read types needed by that projection.
Recorded heart rate, sport-specific power/speed, cycling cadence and supported
running dynamics become quantities in canonical units. Recorded distance and
metabolic energy become one total each; cumulative streams are not added again.
Missing totals are not inferred. Start/end and explicit pause/resume events drive
HealthKit timing; its derived duration/statistics can differ from recorded summaries.
Routes retain timestamps and latitude/longitude. Canonical data has no GPS accuracy,
so the writer uses Core Location's unknown-accuracy sentinel and omits altitude.
Laps, running cadence, notes, tags, calculated summaries and unsupported extensions
are not a lossless HealthKit projection. This is an explicit platform copy, not a backup.

A SHA-256 identity scopes each export to origin, authenticated owner, workout and
revision. Quantities, workout and route carry stable HealthKit sync identifiers;
a newer backend revision is an explicit separate copy, not an automatic overwrite.
The process-wide coordinator prevents simultaneous attempts for one identity.
An atomic JSON journal in Application Support is excluded from backup and uses
complete file protection on iOS. It contains the confirmed snapshot while pending;
completion removes the health payload and retains only receipt bookkeeping.
The detail screen resumes a pending older revision before offering the current one.

HealthKit and HTTP do not form one transaction. `HKWorkoutBuilder.addSamples` may
save quantities before `finishWorkout`; retries reuse this app's matching quantities.
A failed or cancelled build can leave those quantities awaiting recovery, rather
than implying that cancellation undid platform writes. The journal marks an attempt
before finishing the workout or route. Unknown finish results are queried on retry;
an empty read never proves that the write failed and never triggers another finish.
A known workout without a committed route resumes its separate route builder.
The writer confirms associated quantity identities and route points before returning
success. Only then does the client record the exact revision and HealthKit UUID
through the backend receipt endpoint. A failed receipt request resumes HTTP only.

If a write outcome stays unreadable, recovery remains pending instead of risking a
duplicate. Unlocking and restoring read access may make it recoverable; the app does
not promise automatic repair of missing/deleted platform objects. Deleting the
backend workout while a receipt is pending prevents that receipt from being recorded.
Uninstalling the app removes the local journal. No background sync, source merging,
or automatic deletion of HealthKit records is introduced.

The import picker excludes this app's source and explicit export metadata. Durable
backend receipts additionally suppress their owner-scoped HealthKit object UUIDs,
including after the canonical workout is deleted. These are loop-prevention rules,
not cross-source workout merging.

Physical acceptance still needs a signed device: grant/deny individual data types,
export both sports, inspect units and route points, lock during writes, interrupt
between workout/route/receipt, edit the backend during recovery, relaunch, and check
that a retry does not create duplicates. The core tests model failure boundaries;
the simulator exercises synthetic platform writes. Neither replaces those device checks.

Apple references: [workout builder](https://developer.apple.com/documentation/healthkit/hkworkoutbuilder),
[sync identifiers](https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier),
and [workout routes](https://developer.apple.com/documentation/healthkit/creating-a-workout-route).

## Native presentation

The iOS interface uses system grouped backgrounds, large continuous cards,
Dynamic Type, SF Symbols and standard navigation, tabs, pickers and sheets.
Workout history groups the loaded records by calendar month without additional
network requests. Its cards show the existing summary; the list API has no route
preview, so maps remain in workout details.

Details initially show distance and timer duration, then available routes and
measurement charts. Other recorded summaries, calculated summaries and the list
of missing measurements expand on demand. Missing values remain explicit and
are never replaced with zero. Heart rate is red, power purple and speed blue;
charts retain the actual samples and linear guide lines. Accessibility text sizes
stack paired values vertically. Import previews reuse the same presentation
without nesting card backgrounds. Health export keeps its projection limitations
available in an expandable explanation before the existing explicit confirmation.

The visual direction follows a native health application: fewer fields shown by
default, comfortable type and spacing, minimal decoration, and platform behavior
before custom controls. No analytical metrics, source metadata or social features
are inferred from visual references. Check light/dark appearance, accessibility
text sizes and the existing isolated UI integration flow when changing presentation.

## Best-duration power

Detail time-series charts render at most 600 original points, selecting each
bucket's minimum and maximum in time order and preserving the first/last sample.
Dense series omit per-point symbols to bound Swift Charts/Metal rendering work.
The UI labels reduced overviews; full samples, exports and backend calculations
are unchanged. Simulator coverage includes five streams of 12,001 samples.

Workout detail shows a native Swift Charts power-duration section after the power
samples, including cycling and running. It uses the generated authenticated
`power-curve` operation through `PowerCurveStore`; no power calculation is duplicated
on device. The logarithmic duration chart, duration picker and expandable result
list show mean watts and best intervals relative to workout start. Insufficient
continuous coverage has an explicit empty state. Failures offer retry, revision
mismatches offer a workout refresh, and cancellation/session guards discard late
responses. The detail screen owns the refresh task so removing the curve section
during reload cannot cancel the workout request. Curves remain in view-owned memory
only. Summary-only power displays an unavailable message without a curve request;
workouts with neither power samples nor a recorded power summary omit the section.
The sampling-gap explanation uses the backend response threshold.

The isolated simulator harness seeds a 60-second, 200 W effort and exercises the
native result and duration picker. A loopback test proxy forwards requests to the
real backend and changes the first curve revision per workout, making the stale
revision refresh/unmount regression deterministic. Core tests cover wire decoding,
revision mismatch, retry, cancellation and session isolation. Swift contract tests
also cover 12-digit fractional timestamps without reducing backend precision.

The disposable iOS harness explicitly enables analysis-failure controls in its
loopback-only test proxy via `FITNESS_TEST_ANALYSIS_FAILURE_CONTROLS=1`. The UI
regression toggles `POST /__test/analysis-failure/on` and `/off` to verify raw
metrics, comparison axes, the independent power curve, and derived-analysis
retry. These controls are absent from the production backend and disabled in
the proxy unless explicitly enabled. Each UI scenario resets proxy fault state through `POST /__test/reset`, so the
one-shot stale curve does not depend on test order. Reset is guarded by the same
explicit test-only flag. The default harness requires the UI suite to run without skips.


## Localization

The app supports English and Simplified Chinese through iOS system/per-app language
selection. English is the development language and fallback. Native language
negotiation handles regional English and Chinese script/region aliases; unsupported
languages fall back to English. Language selection does not change metric units,
server identifiers, revisions, authorization, or import/export data. Region and
device time zone control date and number formatting. User titles, names, notes,
tags and equipment names remain verbatim.

`App/Localizable.xcstrings` owns UI copy and `App/InfoPlist.xcstrings` owns HealthKit
permission purposes. Both are explicitly included in the Xcode app resource phase;
`FitnessCore` carries semantic errors and metric labels without app-bundle lookups.
Custom title and error components retain `LocalizedStringResource` until rendering,
where they apply the SwiftUI environment locale. Whole messages retain typed
interpolation; count-dependent actions and summaries use native plural variations.
Never translate backend diagnostic prose or construct keys from user content.

Build the app to refresh native compiler extraction, then run:

```sh
python3 ios/check_localizations.py
swift ios/Tests/Support/verify_localizations.swift \
  ios/DerivedData/Build/Products/Debug-iphonesimulator/Fitness.app
python3 ios/check_localizations.py --extracted \
  ios/DerivedData/Build/Intermediates.noindex/Fitness.build/Debug-iphonesimulator/Fitness.build/Objects-normal/arm64
```

Every app build runs the catalog-integrity check, so missing translations or invalid
arguments fail the build. The explicit extraction check also verifies source keys.
The check verifies both translations, typed placeholders, plural branches and keys
from the completed Xcode build. Its in-memory corruption probes demonstrate that
missing translations, wrong argument types and missing plural branches fail.
The Swift helper checks compiled native resources, English singular/plural forms,
Chinese counts, resource-locale changes, missing-key fallback, verbatim content and
the bundled permission purposes.
Keep catalogs in Git; compiler extraction and compiled resources are build outputs.

The isolated UI harness includes English (`en-GB`) and Simplified Chinese login,
workout, settings and HealthKit preview journeys, plus unsupported-language fallback
and `zh-CN` negotiation with localized endpoint errors. Existing Chinese regressions
now launch explicitly in Chinese. XCTest language/locale launch arguments are test
configuration only; application code never changes `AppleLanguages`.
Device HealthKit permission behavior and large-text/pseudolocale acceptance still
require their separate platform checks.


### Localization verification — 2026-09-20 continuation

The final app built on Xcode 27 with the catalog-validation phase enabled.
All **388 catalog entries**, compiler-extracted keys and compiled English/Chinese
resources passed validation, including context-specific titles, plurals, fallback
and both HealthKit purpose descriptions. **61 FitnessCore tests passed**.

The four targeted UI methods have passing results against disposable PostgreSQL
backends on fresh iPhone 15 / iOS 27 simulators: bilingual login/workout/settings/
HealthKit-preview journeys; unsupported-language and Chinese-regional fallback;
body/equipment persistence and backend parameter use; and login/restoration/logout
with synthetic HealthKit writes, receipts and repeated export after relaunch.
The final four-method run passed the first three; the remaining method passed
separately after adapting its test-only iOS 27 historical-data permission step.
This is not a fresh passing run of the entire older UI suite.

Each test resets the proxy's one-shot fault state. Native label assertions retain
both label and value without depending on locale-specific accessibility punctuation.
Analysis rows combine their label/value for accessibility, and numeric fields use
an explicit row so English parameter labels are not clipped. Current English and
Chinese field screenshots and the persisted **72.5 kg / 240 W** analysis readout
were visually inspected. Screenshots contain synthetic data and remain local,
outside maintained source. Physical-device permissions, large-text/pseudolocale
coverage and the full older UI suite remain separate verification boundaries.

### Numeric input validation

Settings and initial CTL/ATL inputs consume the entire localized numeric string.
Malformed suffixes, repeated decimal separators and nonfinite values are rejected;
locale-specific decimal/grouping syntax is retained. `NumericInputTests` covers
English, Simplified Chinese and comma-decimal locales, and the settings UI journey
checks that an invalid weight is rejected without persistence, then verifies a
valid submission.

Review-fix verification on 2026-09-21 passed **63 FitnessCore tests** and exercised
all eight UI scenarios against disposable PostgreSQL backends on iPhone 15 / iOS
17.5 simulators. Seven scenarios passed in the full run; the settings scenario
passed in a focused rerun after accounting for lazy form rows and avoiding cursor
position assumptions. Its result also verifies rejected input is not persisted,
valid parameters survive relaunch, and the backend uses the saved weight/power.
The harness detects the newer Xcode result reader's required legacy-schema flag.
No physical iPhone or Android phone was connected; device verification remains open.
