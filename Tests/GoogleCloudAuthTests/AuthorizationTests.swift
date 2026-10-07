import Foundation
import NIO
import Testing

@testable import GoogleCloudAuth

@Suite struct AuthorizationTests {

  @Test func getAccessTokenNotExpiredTwice() async throws {
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let mockProvider = MockProvider(expiration: .absolute(Date().addingTimeInterval(3600)))
    let authorization = Authorization(
      scopes: ["https://www.googleapis.com/auth/cloud-platform"], provider: mockProvider,
      eventLoopGroup: eventLoopGroup)

    let token1 = try await authorization.accessToken()
    #expect(token1 == "token1")
    await #expect(mockProvider.createSessionCallCount == 1)

    let token2 = try await authorization.accessToken()
    #expect(token2 == "token1")
    await #expect(mockProvider.createSessionCallCount == 1)

    try await authorization.shutdown()
    await #expect(mockProvider.shutdownCallCount == 1)
  }

  @Test func getAccessTokenExpiredTwice() async throws {
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let mockProvider = MockProvider(expiration: .always)
    let authorization = Authorization(
      scopes: ["https://www.googleapis.com/auth/cloud-platform"], provider: mockProvider,
      eventLoopGroup: eventLoopGroup)

    let token1 = try await authorization.accessToken()
    #expect(token1 == "token1")
    await #expect(mockProvider.createSessionCallCount == 1)

    let token2 = try await authorization.accessToken()
    #expect(token2 == "token2")
    await #expect(mockProvider.createSessionCallCount == 2)

    try await authorization.shutdown()
    await #expect(mockProvider.shutdownCallCount == 1)
  }

  @Test func failedSessionIsNotCached() async throws {
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let mockProvider = MockProvider(expiration: .never)
    await mockProvider.setFailing(true)
    let authorization = Authorization(
      scopes: ["https://www.googleapis.com/auth/cloud-platform"], provider: mockProvider,
      eventLoopGroup: eventLoopGroup)

    await #expect(throws: MockProvider.CreateSessionError.self) {
      try await authorization.accessToken()
    }

    await mockProvider.setFailing(false)
    let callCountBeforeRecovery = await mockProvider.createSessionCallCount
    _ = try await authorization.accessToken()
    await #expect(mockProvider.createSessionCallCount == callCountBeforeRecovery + 1)

    try await authorization.shutdown()
  }

  @Test func sessionExpiringSoonIsRefreshed() async throws {
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let mockProvider = MockProvider(expiration: .absolute(Date().addingTimeInterval(30)))
    let authorization = Authorization(
      scopes: ["https://www.googleapis.com/auth/cloud-platform"], provider: mockProvider,
      eventLoopGroup: eventLoopGroup)

    #expect(try await authorization.accessToken() == "token1")
    #expect(try await authorization.accessToken() == "token2")

    try await authorization.shutdown()
  }

  private actor MockProvider: Provider {

    struct CreateSessionError: Error {}

    var createSessionCallCount = 0
    var shutdownCallCount = 0
    var currentSession: Session?
    var isFailing = false

    let expiration: Session.Expiration

    init(expiration: Session.Expiration) {
      self.expiration = expiration
    }

    func setFailing(_ isFailing: Bool) {
      self.isFailing = isFailing
    }

    func createSession(scopes: [Scope], eventLoopGroup: EventLoopGroup) async throws -> Session {
      createSessionCallCount += 1
      if isFailing {
        throw CreateSessionError()
      }
      return Session(
        accessToken: "token\(createSessionCallCount)",
        expiration: expiration
      )
    }

    func shutdown() async throws {
      shutdownCallCount += 1
    }
  }
}
