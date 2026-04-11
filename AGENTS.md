# AGENTS.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project snapshot
- This repo is a Swift Package (`Package.swift`) that builds a reusable networking library named `SwiftAPIService`.
- Platform targets: iOS 16+ and macOS 13+.
- External dependencies: Alamofire (`from: 5.10.0`), AppAuth-iOS (`from: 1.7.0`).
- Tests use Swift Testing (`import Testing` and `@Test`), not XCTest.

## Commands
Run commands from the repository root.

### Build
```sh
swift build
```

### Run all tests
```sh
swift test
```

### Run a single test
Use SwiftPM test filtering with the test function name (or a substring):
```sh
swift test --filter keychainStoreAndRead
```
Example with a broader match:
```sh
swift test --filter apiError
```

### Resolve dependencies
```sh
swift package resolve
```

### Linting / formatting
- There is no repository-configured lint/format command (no SwiftLint/SwiftFormat config is present in this repo).

## High-level architecture
The library is organized around a small set of protocols and one main client implementation.

### Core flow
1. Consumer defines an `APIEnvironment` (base URL, default headers, timeout).
2. Consumer defines endpoints conforming to `APIEndpoint` (path/method/query/body/status range).
3. Consumer creates `APIClient.Configuration` and `APIClient`.
4. `APIClient` builds an Alamofire `Session` with composed interceptors and optional event monitors.
5. Requests are executed with async/await (`request`, `upload`, `requestText`) or legacy-compatible `dispatch*` methods.
6. Failures are normalized to `APIError`.

### Important modules
- `Sources/SwiftAPIService/Client/APIClient.swift`
  - Main orchestration layer.
  - Builds `URLSessionConfiguration`, merges environment headers, composes interceptors (`AuthInterceptor`, `RetryPolicy`, additional interceptors), and attaches logging monitors.
  - Exposes modern endpoint-based API plus legacy-compatible methods (`dispatch`, `dispatchUpload`, `dispatchText`) for migration from older call sites.

- `Sources/SwiftAPIService/Endpoint/APIEndpoint.swift`
  - Protocol defining request shape and response validation bounds.
  - Includes URL construction helper relative to environment base URL.

- `Sources/SwiftAPIService/Configuration/APIEnvironment.swift`
  - Protocol for deployment-specific values (base URL, default headers, timeout).

- `Sources/SwiftAPIService/Auth/`
  - `TokenStore.swift`: actor-backed credential storage, persisted via Keychain. `AuthCredential` includes optional `idToken` and `accessTokenExpirationDate` for OIDC.
  - `AuthInterceptor.swift`: Alamofire `RequestInterceptor` that attaches bearer tokens and handles 401 refresh retry.
  - `TokenRefreshProvider.swift`: protocol the host app must implement for refresh API behavior.

- `Sources/SwiftAPIService/Security/KeychainService.swift`
  - Thin Security.framework wrapper used by `TokenStore`.

- `Sources/SwiftAPIService/Errors/APIError.swift`
  - Central error translation from Alamofire/network/HTTP/decoding failures to typed `APIError.Kind`.

- `Sources/SwiftAPIService/Logging/APILogger.swift`
  - Alamofire `EventMonitor` backed by `os.log`; enabled via `APIClient.Configuration.logLevel`.

- `Sources/SwiftAPIService/OIDC/`
  - `OIDCConfiguration.swift`: OIDC provider/client configuration (issuer, clientID, redirectURI, scopes).
  - `OIDCAuthService.swift`: orchestrates OIDC discovery, PKCE login via AppAuth's `OIDAuthState`, session restore, and logout.
  - `OIDCTokenRefreshProvider.swift`: concrete `TokenRefreshProvider` using AppAuth's `OIDTokenRequest` with `refresh_token` grant.
  - `OIDCPresentationContext.swift`: platform-specific protocol (`UIViewController` on iOS, `NSWindow` on macOS) and AppAuth external user agent bridge.
  - `OIDCError.swift`: typed error enum for OIDC flow failures.

### Auth and retry behavior to preserve
- `AuthInterceptor` coalesces concurrent 401 refresh attempts behind a lock, queues pending retries, then resolves all queued requests once refresh succeeds/fails.
- On refresh failure, tokens are cleared from `TokenStore` and pending requests fail with `.tokenRefreshFailed`.
- `APIClient` can combine auth interception with `RetryPolicy` and additional interceptors; keep ordering/composition intentional when modifying bootstrap logic.

## Test layout
- Test target: `Tests/SwiftAPIServiceTests`.
- Tests cover: keychain persistence, `APIError` mapping, SSE parsing/retry, `OIDCConfiguration`, `OIDCError`, `AuthCredential` OIDC fields, `TokenStore` OIDC persistence, and `OIDCAuthService` unit-testable paths (restore, logout, init safety).
