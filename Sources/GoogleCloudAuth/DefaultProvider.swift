import NIO
import Logging

/// A default implementation of the `Provider` protocol that manages authentication sessions.
public actor DefaultProvider: Provider {

    /// A shared instance of `DefaultProvider` for convenient access.
    public static let shared = DefaultProvider()

    public func createSession(scopes: [Scope], eventLoopGroup: EventLoopGroup) async throws -> Session {
        try await provider.createSession(scopes: scopes, eventLoopGroup: eventLoopGroup)
    }

    public func shutdown() async throws {
        try await provider.shutdown()
    }

    private var _provider: Provider?

    var provider: Provider {
        get async throws {
            if let _provider {
                return _provider
            }
            let provider = try await resolveProvider()
            self._provider = provider
            return provider
        }
    }

    fileprivate func resetProvider() async throws {
        try await _provider?.shutdown()
        _provider = nil
    }

    private nonisolated func resolveProvider() async throws -> Provider {
        let logger = Logger(label: "authorization.default-provider")

        // 1. User explicitly set a provider
        if let provider = await DefaultProviderCoordinator.shared.provider {
            return provider
        }

        // 2. Try to use default service account credentials
        if let serviceAccountProvider = try ServiceAccountProvider() {
            return serviceAccountProvider
        }

        // 3. Try to use gcloud configured credentials
        if let googleCloudSDKProvider = try GoogleCloudSDKProvider() {
            logger.warning("""
Your application has authenticated using end user credentials from Google
Cloud SDK. We recommend that most server applications use service accounts
instead. If your application continues to use end user credentials from Cloud
SDK, you might receive a "quota exceeded" or "API not enabled" error. For
more information about service accounts, see
https://cloud.google.com/docs/authentication/.
""")
            return googleCloudSDKProvider
        }

        // 4. Fallback to assume running in GCP
        return MetadataProvider()
    }
}

/// A system for managing the default authorization provider.
public struct AuthorizationSystem {

    private static let logger = Logger(label: "authorization.system")

    /// Bootstraps the authorization system with a custom provider.
    /// - Parameter defaultProvider: The custom `Provider` to use as the default.
    /// - Precondition: The `defaultProvider` must not be an instance of `DefaultProvider`.
    public static func bootstrap(_ defaultProvider: Provider) async {
        precondition(!(defaultProvider is DefaultProvider), "Must not use default provider as authorization system. This may result in recursion.")

        do {
            try await DefaultProvider.shared.resetProvider()
        } catch {
            logger.error("Failed to shutdown old provider: \(error)")
        }
        await DefaultProviderCoordinator.shared.use(defaultProvider)
    }
}

actor DefaultProviderCoordinator {

    static let shared = DefaultProviderCoordinator()

    var provider: Provider?

    func use(_ provider: Provider) {
        self.provider = provider
    }
}
