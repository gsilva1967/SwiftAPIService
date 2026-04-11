# SwiftAPIService

A production-ready Swift Package that provides a reusable API client built on top of Alamofire with:

- **Token-based authentication** with automatic refresh and retry
- **OIDC / OAuth 2.0 authentication** via AppAuth (discovery, PKCE login, token refresh, logout)
- **Secure Keychain storage** (no UserDefaults)
- **Protocol-based endpoint abstraction**
- **Typed error handling**
- **Structured logging** via `os.log`
- **Environment configuration** (dev / staging / prod)
- **Server-Sent Events (SSE)** streaming with reconnect, backoff, and `Last-Event-ID` continuity
- **Full Swift 6 concurrency safety** (`Sendable`, `actor`)

## Requirements

- Swift 6.0+
- iOS 16+ / macOS 13+
- Alamofire 5.10+
- AppAuth 1.7+ (for OIDC/OAuth2 features)

## Installation

Add via Swift Package Manager:

```swift
.package(url: "https://github.com/your-org/SwiftAPIService.git", from: "1.0.0")
```

Or add the local package in Xcode: **File → Add Package Dependencies → Add Local...**

---

## Quick Start

### 1. Define your environment

```swift
import SwiftAPIService

enum AppEnvironment: APIEnvironment {
    case dev, staging, prod

    var baseURL: URL {
        switch self {
        case .dev:     URL(string: "https://dev-api.example.com")!
        case .staging: URL(string: "https://staging-api.example.com")!
        case .prod:    URL(string: "https://api.example.com")!
        }
    }

    var defaultHeaders: [String: String] {
        [
            "apikey": "your-api-key",
            "apptoken": "your-app-token",
        ]
    }

    var timeoutInterval: TimeInterval { 15 }
}
```

### 2. Define endpoints

```swift
enum UserEndpoint: APIEndpoint {
    case profile(id: String)
    case updateProfile(ProfilePayload)

    var path: String {
        switch self {
        case .profile(let id): "/users/\(id)"
        case .updateProfile:   "/users/profile"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .profile:       .get
        case .updateProfile: .put
        }
    }

    var body: (any Encodable & Sendable)? {
        switch self {
        case .updateProfile(let payload): payload
        default: nil
        }
    }
}
```

### 3. Implement the token refresh provider

```swift
struct MyTokenRefresher: TokenRefreshProvider {
    func refresh(using refreshToken: String) async throws -> AuthCredential {
        // Call your backend's refresh endpoint (use a separate, non-intercepted session)
        let response = try await refreshSession
            .request("https://api.example.com/auth/refresh",
                     method: .post,
                     parameters: ["refresh_token": refreshToken])
            .serializingDecodable(TokenResponse.self)
            .value

        return AuthCredential(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken
        )
    }
}
```

### 4. Bootstrap the client

```swift
// Keychain for secure token persistence
let keychain = KeychainService(service: "com.yourapp.api")

// Token store (actor-based, thread-safe)
let tokenStore = TokenStore(keychain: keychain)

// Auth interceptor
let authInterceptor = AuthInterceptor(
    tokenStore: tokenStore,
    refreshProvider: MyTokenRefresher()
)

// Retry policy for transient server errors
let retryPolicy = RetryPolicy(
    retryLimit: 3,
    retryableHTTPStatusCodes: [408, 500, 502, 503, 504]
)

// Create the client
let apiClient = APIClient(configuration: .init(
    environment: AppEnvironment.dev,
    tokenStore: tokenStore,
    authInterceptor: authInterceptor,
    retryPolicy: retryPolicy,
    logLevel: .verbose  // .none / .errors / .info / .verbose
))
```

### 5. Make requests

```swift
// JSON request (modern endpoint-based API)
let user: User = try await apiClient.request(UserEndpoint.profile(id: "42"))

// Text response
let html = try await apiClient.requestText(SomeEndpoint.termsOfService)

// Multipart upload
let result: UploadResult = try await apiClient.upload(
    MediaEndpoint.avatar,
    fileData: imageData,
    fileName: "avatar.jpg",
    mimeType: "image/jpeg",
    parameters: ["userId": "42"]
)

// Legacy-compatible dispatch (drop-in replacement for Safeguard APIService)
let facilities: [Facility] = try await apiClient.dispatch(
    httpMethod: .get,
    endPoint: "https://api.example.com/facilities",
    resultType: [Facility].self
)
```

### 6. Handle errors

```swift
do {
    let data: MyModel = try await apiClient.request(SomeEndpoint.data)
} catch let error as APIError {
    switch error.kind {
    case .unauthorized:
        // Navigate to login
        break
    case .noConnection:
        // Show offline banner
        break
    case .timeout:
        // Suggest retry
        break
    case .decodingError:
        // Log to crash reporting
        break
    default:
        print(error.description)
    }
}
```

---

## Server-Sent Events (SSE)

Use `SSEEndpoint` + `APIClient.stream(...)` to consume `text/event-stream` endpoints as an async sequence.

### Define an SSE endpoint

```swift
enum StreamEndpoint: SSEEndpoint {
    case events

    var path: String { "/events" }
}
```

### Consume the stream

```swift
for try await event in apiClient.stream(StreamEndpoint.events) {
    print(event.event ?? "message", event.data)
}
```

### Decode typed payloads

```swift
struct StreamPayload: Decodable {
    let message: String
}

for try await event in apiClient.stream(StreamEndpoint.events) {
    let payload = try event.decodeData(as: StreamPayload.self)
    print(payload.message)
}
```

### Customize stream behavior

```swift
let streamConfig = SSEStreamConfiguration(
    retryStrategy: SSERetryStrategy(
        baseDelayMilliseconds: 1_000,   // initial reconnect delay
        maxDelayMilliseconds: 30_000,   // cap on exponential backoff
        maxAttempts: 5,                 // nil = unlimited
        jitterRatio: 0.1               // ±10% randomisation
    ),
    lastEventID: nil,                  // resume from a known event ID
    validateContentType: true,         // enforce text/event-stream
    requestTimeout: 30,                // per-connection timeout
    unauthorizedRefreshRetryLimit: 1   // 401 refresh attempts before failing
)

for try await event in apiClient.stream(StreamEndpoint.events, configuration: streamConfig) {
    print(event.data)
}
```

### Reconnection behavior

- Streams are exposed as `AsyncThrowingStream<SSEEvent, Error>` to provide natural backpressure and cancellation with Swift concurrency.
- Reconnection uses `SSERetryStrategy` (exponential backoff + optional jitter), while respecting server-provided `retry` values when present.
- The latest event `id` is persisted in memory and sent via `Last-Event-ID` on reconnect to reduce duplicate deliveries.

### Authentication behavior

- SSE requests include the current bearer token from `TokenStore`.
- If the server responds with `401`, the client can attempt credential refresh (when `AuthInterceptor` is configured) and reconnect.
- If refresh fails (or retry limit is reached), the stream fails with `SSEError.unauthorized`.

### Why URLSession for SSE (instead of Alamofire)?

Alamofire is still used as the core transport layer for request/response APIs and interceptor composition, but SSE uses `URLSession` async bytes streaming because it is the most direct, stable fit for long-lived line-delimited event streams in Swift concurrency. This keeps the API consistent with the package while avoiding extra indirection for stream parsing and reconnection control.

---

## OIDC / OAuth 2.0 Authentication

SwiftAPIService includes a built-in OIDC/OAuth2 layer powered by [AppAuth](https://github.com/openid/AppAuth-iOS). It handles service discovery, PKCE-secured authorization, token exchange, refresh, and logout — all storing credentials through the existing `TokenStore` and plugging into `AuthInterceptor` for automatic 401 retry.

### 1. Configure the OIDC provider

```swift
let oidcConfig = OIDCConfiguration(
    issuer: URL(string: "https://accounts.google.com")!,
    clientID: "your-client-id",
    redirectURI: URL(string: "com.yourapp://callback")!,
    scopes: ["openid", "profile", "email", "offline_access"]
)
```

### 2. Create the auth service

```swift
let keychain = KeychainService(service: "com.yourapp.api")
let tokenStore = TokenStore(keychain: keychain)
let oidcService = OIDCAuthService(configuration: oidcConfig, tokenStore: tokenStore)
```

### 3. Login

Present the system browser for the OIDC authorization flow:

```swift
// Implement the presentation context protocol
class MyPresenter: OIDCPresentationContextProviding {
    @MainActor func presentingContext() -> OIDCPresentingContext {
        // iOS: return the root UIViewController
        // macOS: return the key NSWindow
    }
}

let credential = try await oidcService.login(presentationContext: MyPresenter())
```

AppAuth handles PKCE code challenge generation, browser presentation via `OIDExternalUserAgentIOS` / `OIDExternalUserAgentMac`, callback parsing, and token exchange automatically.

### 4. Wire into the API client

After login (or session restore), `tokenRefreshProvider` is available:

```swift
let authInterceptor = AuthInterceptor(
    tokenStore: tokenStore,
    refreshProvider: oidcService.tokenRefreshProvider!
)

let apiClient = APIClient(configuration: .init(
    environment: AppEnvironment.dev,
    tokenStore: tokenStore,
    authInterceptor: authInterceptor
))
```

All requests now automatically include the Bearer token, and 401 responses trigger a transparent token refresh via AppAuth.

### 5. Restore session on app launch

```swift
if let credential = try await oidcService.restoreSession() {
    // Tokens exist in Keychain — tokenRefreshProvider is ready.
    // Build APIClient as above.
} else {
    // No stored session — show login.
}
```

### 6. Logout

```swift
let endSessionURL = await oidcService.logout()
// Tokens are cleared. If the provider supports RP-Initiated Logout,
// endSessionURL contains the end_session_endpoint with id_token_hint.
```

### OIDC credential fields

`AuthCredential` now includes optional OIDC fields (backward compatible):

```swift
let credential = AuthCredential(
    accessToken: "...",
    refreshToken: "...",
    idToken: "eyJ...",                       // OIDC ID token (JWT)
    accessTokenExpirationDate: Date(...)     // Token expiry
)

credential.isAccessTokenExpired  // Convenience check
```

### Configuration options

```swift
OIDCConfiguration(
    issuer: issuerURL,              // OIDC issuer (used for discovery)
    clientID: "...",                // OAuth client ID
    clientSecret: nil,              // Optional (native apps use PKCE)
    redirectURI: redirectURL,       // Must match provider registration
    scopes: ["openid"],             // OAuth/OIDC scopes
    additionalParameters: [:],      // Extra authorization params
    prefersEphemeralSession: false  // true = no shared browser cookies
)
```

---

## Architecture Overview

```
SwiftAPIService/
├── Sources/SwiftAPIService/
│   ├── SwiftAPIService.swift              # Barrel re-export (re-exports Alamofire)
│   ├── Configuration/
│   │   └── APIEnvironment.swift           # Environment protocol (base URL, headers, timeout)
│   ├── Endpoint/
│   │   └── APIEndpoint.swift              # Endpoint protocol (path, method, body, status)
│   ├── Client/
│   │   └── APIClient.swift                # Main API client + SSE stream entry point
│   ├── Auth/
│   │   ├── TokenStore.swift               # Actor-based credential store (Keychain-backed)
│   │   ├── AuthInterceptor.swift          # RequestInterceptor (adapt + 401 retry)
│   │   └── TokenRefreshProvider.swift     # Protocol for app-specific refresh logic
│   ├── Security/
│   │   └── KeychainService.swift          # Security.framework Keychain wrapper
│   ├── Errors/
│   │   └── APIError.swift                 # Typed error model + factory helpers
│   ├── Logging/
│   │   └── APILogger.swift                # os.log-backed Alamofire EventMonitor
│   ├── SSE/
│   │   ├── SSEEndpoint.swift              # SSEEndpoint protocol
│   │   ├── SSEEvent.swift                 # Parsed SSE frame + decodeData helper
│   │   ├── SSEError.swift                 # SSE-specific error cases
│   │   ├── SSERetryStrategy.swift         # Exponential backoff + jitter policy
│   │   └── SSEStreamConfiguration.swift   # Runtime stream config + SSEParser + SSEConnection
│   └── OIDC/
│       ├── OIDCConfiguration.swift        # OIDC provider/client configuration
│       ├── OIDCAuthService.swift          # Discovery, login (PKCE), restore, logout
│       ├── OIDCTokenRefreshProvider.swift  # AppAuth-based TokenRefreshProvider
│       ├── OIDCPresentationContext.swift   # Platform presentation protocol + agent bridge
│       └── OIDCError.swift                # OIDC-specific error cases
└── Tests/SwiftAPIServiceTests/
    ├── SwiftAPIServiceTests.swift         # Keychain + APIError tests
    ├── SSETests.swift                     # SSEParser + SSERetryStrategy + SSEEvent tests
    └── OIDCTests.swift                    # OIDCConfiguration + credential + token store + auth service tests
```

---

## Development

### Build

```sh
swift build
```

### Run tests

```sh
swift test
```

Run a single test by name:

```sh
swift test --filter sseParserParsesEventFields
```

---

## Token Refresh Flow

1. `AuthInterceptor.adapt()` attaches the current access token as a `Bearer` header on every request.
2. When a response returns **HTTP 401**, `AuthInterceptor.retry()` is called.
3. The interceptor uses an `NSLock` to ensure only **one** refresh call happens at a time — additional 401s during the refresh are queued.
4. It calls `TokenRefreshProvider.refresh(using:)` with the current refresh token.
5. On success, the new credential is stored in the `TokenStore` (actor → Keychain), and all queued requests are retried.
6. On failure, tokens are cleared and all queued requests fail with `.tokenRefreshFailed`.

## How the Interceptor Works

- **`adapt(_:for:completion:)`** — Called before every request. Reads the access token from the `TokenStore` actor and sets the `Authorization` header.
- **`retry(_:for:dueTo:completion:)`** — Called when a request fails. Checks for 401, then triggers the refresh-and-retry cycle described above.
- Uses Alamofire's standard `RequestInterceptor` protocol, which is composable with `RetryPolicy` and other interceptors via `Interceptor(interceptors:)`.

## Migrating from Safeguard's APIService

The `APIClient` includes **legacy-compatible** methods that mirror the existing signatures:

| Safeguard method       | SwiftAPIService equivalent        |
|------------------------|---------------------------------|
| `dispatch()`           | `apiClient.dispatch()`          |
| `dispatchUpload()`     | `apiClient.dispatchUpload()`    |
| `dispatchText()`       | `apiClient.dispatchText()`      |

For new code, prefer the endpoint-based `request()`, `upload()`, and `requestText()` methods.
