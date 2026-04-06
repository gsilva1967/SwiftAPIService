# SwiftAPIService

A production-ready Swift Package that provides a reusable API client built on top of Alamofire with:

- **Token-based authentication** with automatic refresh and retry
- **Secure Keychain storage** (no UserDefaults)
- **Protocol-based endpoint abstraction**
- **Typed error handling**
- **Structured logging** via `os.log`
- **Environment configuration** (dev / staging / prod)
- **Full Swift 6 concurrency safety** (`Sendable`, `actor`)

## Requirements

- Swift 6.0+
- iOS 16+ / macOS 13+
- Alamofire 5.10+

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

## Architecture Overview

```
SwiftAPIService/
├── Sources/SwiftAPIService/
│   ├── SwiftAPIService.swift          # Barrel re-export
│   ├── Configuration/
│   │   └── APIEnvironment.swift     # Environment protocol (dev/staging/prod)
│   ├── Endpoint/
│   │   └── APIEndpoint.swift        # Endpoint protocol
│   ├── Client/
│   │   └── APIClient.swift          # Main API client
│   ├── Auth/
│   │   ├── TokenStore.swift         # Actor-based credential store
│   │   ├── AuthInterceptor.swift    # RequestInterceptor (adapt + retry)
│   │   └── TokenRefreshProvider.swift # Protocol for refresh logic
│   ├── Security/
│   │   └── KeychainService.swift    # Keychain wrapper
│   ├── Errors/
│   │   └── APIError.swift           # Typed error model
│   └── Logging/
│       └── APILogger.swift          # os.log EventMonitor
└── Tests/SwiftAPIServiceTests/
    └── SwiftAPIServiceTests.swift
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
