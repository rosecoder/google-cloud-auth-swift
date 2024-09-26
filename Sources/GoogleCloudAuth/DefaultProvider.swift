import NIO
import Logging

public actor DefaultProvider: Provider {

    public static let shared = DefaultProvider()

    public func createSession(scopes: [Scope], eventLoopGroup: EventLoopGroup) async throws -> Session {
        try await getProvider().createSession(scopes: scopes, eventLoopGroup: eventLoopGroup)
    }

    public func shutdown() async throws {
        try await getProvider().shutdown()
    }

    struct NotImplementedError: Error {}

    func getProvider() async throws -> Provider {
        // 1. User explicitly set a provider
        if let provider = await DefaultProviderCoordinator.shared.provider {
            return provider
        }

        // 2. Try to use default service account credentials
        if let serviceAccountProvider = try ServiceAccountProvider() {
            return serviceAccountProvider
        }

        // 3. Try to use gcloud configured credentials
        // TODO: Implement

        // 4. Fallback to assume running in GCP
        // TODO: Implement

        throw NotImplementedError()
    }
}

public struct AuthorizationSystem {

    private static let logger = Logger(label: "authorization.system")

    public static func bootstrap(_ defaultProvider: Provider) async {
        precondition(!(defaultProvider is DefaultProvider), "Must not use default provider as authorization system. This may result in recursion.")

        if let oldProvider = await DefaultProviderCoordinator.shared.provider {
            do {
                try await oldProvider.shutdown()
            } catch {
                logger.error("Failed to shutdown old provider: \(error)")
            }
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
