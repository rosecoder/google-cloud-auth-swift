import NIO
import Testing

@testable import GoogleCloudAuth

@Suite(.serialized) struct DefaultProviderTests {

  @Test func bootstrap() async throws {
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    // Default
    _ = try await DefaultProvider.shared.provider

    // Bootstrap 1
    let mockProvider1 = MockProvider()
    await #expect(mockProvider1.createSessionCallCount == 0)
    await #expect(mockProvider1.shutdownCallCount == 0)
    await AuthorizationSystem.bootstrap(mockProvider1)

    #expect(try await DefaultProvider.shared.provider as? MockProvider === mockProvider1)
    #expect(
      try await DefaultProvider.shared.createSession(
        scopes: ["https://www.googleapis.com/auth/cloud-platform"], eventLoopGroup: eventLoopGroup
      ).accessToken == "1")
    await #expect(mockProvider1.createSessionCallCount == 1)
    await #expect(mockProvider1.shutdownCallCount == 0)

    // Bootstrap 2
    let mockProvider2 = MockProvider()
    await #expect(mockProvider2.createSessionCallCount == 0)
    await #expect(mockProvider2.shutdownCallCount == 0)
    await AuthorizationSystem.bootstrap(mockProvider2)

    await #expect(mockProvider1.shutdownCallCount == 1)

    #expect(try await DefaultProvider.shared.provider as? MockProvider === mockProvider2)

    // Shutdown
    try await DefaultProvider.shared.shutdown()

    await #expect(mockProvider1.shutdownCallCount == 1)
    await #expect(mockProvider2.shutdownCallCount == 1)
  }

  private actor MockProvider: Provider {

    var createSessionCallCount = 0
    var shutdownCallCount = 0

    func createSession(scopes: [Scope], eventLoopGroup: EventLoopGroup) async throws -> Session {
      createSessionCallCount += 1
      return Session(
        accessToken: "\(createSessionCallCount)",
        expiration: .never
      )
    }

    func shutdown() async throws {
      shutdownCallCount += 1
    }
  }

  @Test func multipleShutdown() async throws {
    let mockProvider = MockProvider()
    await #expect(mockProvider.createSessionCallCount == 0)
    await #expect(mockProvider.shutdownCallCount == 0)
    await AuthorizationSystem.bootstrap(mockProvider)

    _ = try await DefaultProvider.shared.provider

    try await DefaultProvider.shared.shutdown()
    await #expect(mockProvider.shutdownCallCount == 1)

    try await DefaultProvider.shared.shutdown()
    await #expect(mockProvider.shutdownCallCount == 1)  // should still be 1 because it's already shutdown
  }

  @Test func concurrentShutdownShutsDownProviderOnce() async throws {
    let mockProvider = MockProvider()
    await AuthorizationSystem.bootstrap(mockProvider)
    _ = try await DefaultProvider.shared.provider

    async let first: Void = DefaultProvider.shared.shutdown()
    async let second: Void = DefaultProvider.shared.shutdown()
    _ = try await (first, second)

    await #expect(mockProvider.shutdownCallCount == 1)
  }

  @Test func authorizationShutdownKeepsSharedProviderRunning() async throws {
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let mockProvider = MockProvider()
    await AuthorizationSystem.bootstrap(mockProvider)

    let authorization = Authorization(
      scopes: ["https://www.googleapis.com/auth/cloud-platform"], eventLoopGroup: eventLoopGroup)
    _ = try await authorization.accessToken()
    try await authorization.shutdown()

    await #expect(mockProvider.shutdownCallCount == 0)
    #expect(try await DefaultProvider.shared.provider as? MockProvider === mockProvider)

    try await DefaultProvider.shared.shutdown()
    await #expect(mockProvider.shutdownCallCount == 1)
  }
}
