# AI Fitness for iOS

The native client uses SwiftUI and the shared Servant-generated Swift API client.
It implements native login, Keychain-backed session restoration, server-confirmed
logout, backend workout browsing, and explicit HealthKit-to-backend import.
Backend-to-HealthKit export follows in a separate reviewed slice.

## Build

The current baseline is Xcode 15.4, Swift 5.10, and iOS 17 or later. Select Xcode
with its platform SDKs installed. The macOS core test package requires macOS 14.
The Xcode project is maintained in `Fitness.xcodeproj`; its `FitnessCore` product
comes from this directory's local Swift package. Generated contracts are build
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
power, speed, altitude and sport-specific cadence plots. Display conversions use
kilometres and km/h; running cadence remains total steps/minute and average pace
uses min/km. Missing values remain visibly missing. Sample timestamps are retained;
chart lines are visual guides across samples, not additional measurements.

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
detail, relaunch/restoration and logout scenarios, then removes the
server, database and simulator. Existing `DATABASE_URL` values and devices are not
used. Logs and Xcode results remain in ignored `ios/build` and `ios/DerivedData`.
Running the UI suite without the harness skips the real-backend scenario; that
skip is not evidence of successful integration.

The suite also checks the HealthKit entry screen. It does not authorize, read, or
write real HealthKit records and is not evidence of physical-device HealthKit behavior.

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
