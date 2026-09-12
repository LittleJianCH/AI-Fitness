# AI Fitness iOS core

The native Swift package reuses the Servant-generated `ContractClient`. It provides
native authentication over Apple’s URLSession transport, Keychain credential
storage scoped to the server origin, and an app-owned observable session state.
The SwiftUI application and simulator integration are the next implementation slice.

The baseline is Swift 5.10, iOS 17 and macOS 14 (for portable core tests).
`swift-openapi-urlsession` 1.0.2 supplies the HTTP transport; the existing generator
1.6.0 and runtime 1.7.0 remain pinned. Package resolution is committed, generated
contracts and build outputs are not.

From the repository root, generate the shared contract and test the core:

```sh
nix develop -c make -C backend contract contract-test
nix develop -c bash -c 'cd contracts && node openapi.mjs'
cp contracts/build/openapi.json contracts/swift/Sources/ContractClient/openapi.json
swift test --package-path ios --disable-automatic-resolution
```

SPM may fetch pinned packages on first use. Server origins exclude API paths,
credentials, query strings and fragments. HTTPS is required unless a caller
explicitly enables loopback HTTP for development. Native requests disable cookies
and caching, and refuse HTTP redirects. Generated-client diagnostics are not
rendered or logged because they can include request bodies.

Keychain uses `WhenUnlockedThisDeviceOnly`. Launch restoration verifies credentials
with `/me`: HTTP 401 clears them, while network failures retain them for retry.
Logout is complete only after server confirmation or an invalid-session response.
A local-forget action explicitly does not claim remote revocation. Session
generations prevent old responses from reviving or clearing a different session.

Tests cover restoration, login/logout failures, stale results, credential scoping,
wire requests, safe error presentation and redirect refusal through a real local
HTTP fixture. They do not constitute iOS app, physical-device or HealthKit tests.
