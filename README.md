# Google Cloud Auth for Swift

This package provides a Swift implementation for authenticating with Google Cloud services. It's made for be a server-first solution instead of the official [google-auth-library-swift](https://github.com/googleapis/google-auth-library-swift).

## Example usage

```swift
let authorization = Authorization(scopes: ["https://www.googleapis.com/auth/cloud-platform"], eventLoopGroup: <#eventLoopGroup#>)
let accessToken = try await authorization.accessToken()
print(accessToken)
```

You can also implicitly use a specific method (aka provider) for authentication:

```swift
let authorization = Authorization(
    scopes: ["https://www.googleapis.com/auth/cloud-platform"],
    provider: ServiceAccountProvider(credentials: <#credentials#>),
    eventLoopGroup: <#eventLoopGroup#>
)
```

The default provider can be configured globally by using the `AuthorizationSystem`.

```swift
await AuthorizationSystem.bootstrap(
    ServiceAccountProvider(credentials: <#credentials#>)
)
```

## Supported authentication methods

These are the currently supported authentication methods and default order of the default provider.

### 1. Service Account (JSON key file)

If `GOOGLE_APPLICATION_CREDENTIALS` environment variabl is set, the service account JSON file will be used.

### 2. Google Cloud SDK

If `~/.config/gcloud/application_default_credentials.json` file exists, the Google Cloud SDK credentials will be used.

### 3. Compute Engine, Kubernetes Engine, Cloud Run, App Engine, Cloud Functions

If running on Google Cloud Platform, the metadata server will be used to retrieve the credentials.
