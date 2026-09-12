# AI Fitness for iOS

The native client uses SwiftUI and the shared Servant-generated Swift API client.
The initial slice implements native login, Keychain-backed session restoration,
and server-confirmed logout. Workout browsing and HealthKit integration follow
in separate reviewed commits.

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

```sh
nix develop -c bash scripts/ios_integration_test
```

The script creates a private PostgreSQL cluster with no TCP listener, migrates it,
starts the actual backend on a temporary loopback port, registers a synthetic
account, and creates a dedicated iPhone 15 / iOS 17.5 simulator. It runs the XCUITest
login, wrong-password, relaunch/restoration and logout scenarios, then removes the
server, database and simulator. Existing `DATABASE_URL` values and devices are not
used. Logs and Xcode results remain in ignored `ios/build` and `ios/DerivedData`.
Running the UI suite without the harness skips the real-backend scenario; that
skip is not evidence of successful integration.

No physical-device or HealthKit verification is claimed by these login checks.
