import Foundation
import NIO
import Synchronization
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
    let mockProvider = MockProvider(expiration: .never)
    await mockProvider.setFailing(true)
    let authorization = makeAuthorization(provider: mockProvider, clock: TestClock())

    await #expect(throws: MockProvider.CreateSessionError.self) {
      try await authorization.accessToken()
    }
    await #expect(mockProvider.createSessionCallCount == 3)

    await mockProvider.setFailing(false)
    #expect(try await authorization.accessToken() == "token4")
    await #expect(mockProvider.createSessionCallCount == 4)

    try await authorization.shutdown()
  }

  @Test func failedAttemptsAreRetriedUntilSuccess() async throws {
    let mockProvider = MockProvider(expiration: .never)
    await mockProvider.setFailuresBeforeSuccess(2)
    let authorization = makeAuthorization(provider: mockProvider, clock: TestClock())

    #expect(try await authorization.accessToken() == "token3")
    await #expect(mockProvider.createSessionCallCount == 3)

    try await authorization.shutdown()
  }

  @Test func sessionWithinRefreshMarginIsRefreshedInBackground() async throws {
    let clock = TestClock()
    let mockProvider = MockProvider(expiration: .absolute(clock.now.addingTimeInterval(3600)))
    let authorization = makeAuthorization(provider: mockProvider, clock: clock)

    #expect(try await authorization.accessToken() == "token1")

    clock.advance(by: 3600 - Authorization.refreshMargin - 1)
    #expect(try await authorization.accessToken() == "token1")
    await #expect(mockProvider.createSessionCallCount == 1)

    await mockProvider.setExpiration(.absolute(clock.now.addingTimeInterval(3600)))
    clock.advance(by: 2)
    #expect(try await authorization.accessToken() == "token1")

    try await waitUntil { await mockProvider.createSessionCallCount == 2 }
    try await waitUntil { try await authorization.accessToken() == "token2" }
    await #expect(mockProvider.createSessionCallCount == 2)

    try await authorization.shutdown()
  }

  @Test func sessionWithinExpiryMarginWaitsForRefresh() async throws {
    let clock = TestClock()
    let mockProvider = MockProvider(expiration: .absolute(clock.now.addingTimeInterval(3600)))
    let authorization = makeAuthorization(provider: mockProvider, clock: clock)

    #expect(try await authorization.accessToken() == "token1")

    clock.advance(by: 3600 - Authorization.expiryMargin)
    #expect(try await authorization.accessToken() == "token2")
    await #expect(mockProvider.createSessionCallCount == 2)

    try await authorization.shutdown()
  }

  @Test func sessionWithLifetimeShorterThanMarginIsReused() async throws {
    let clock = TestClock()
    let mockProvider = MockProvider(expiration: .absolute(clock.now.addingTimeInterval(60)))
    let authorization = makeAuthorization(provider: mockProvider, clock: clock)

    #expect(try await authorization.accessToken() == "token1")
    clock.advance(by: 29)
    #expect(try await authorization.accessToken() == "token1")
    await #expect(mockProvider.createSessionCallCount == 1)

    try await authorization.shutdown()
  }

  @Test func concurrentCallersShareOneFetch() async throws {
    let gate = Gate()
    let mockProvider = MockProvider(expiration: .never, gate: gate)
    let authorization = makeAuthorization(provider: mockProvider, clock: TestClock())

    try await withThrowingTaskGroup(of: String.self) { group in
      for _ in 0..<50 {
        group.addTask { try await authorization.accessToken() }
      }
      try await waitUntil { await mockProvider.createSessionCallCount == 1 }
      await gate.open()

      for try await token in group {
        #expect(token == "token1")
      }
    }
    await #expect(mockProvider.createSessionCallCount == 1)

    try await authorization.shutdown()
  }

  @Test func concurrentCallersAtExpiryShareOneFetch() async throws {
    let clock = TestClock()
    let gate = Gate()
    let mockProvider = MockProvider(
      expiration: .absolute(clock.now.addingTimeInterval(3600)), gate: gate)
    await gate.open()
    let authorization = makeAuthorization(provider: mockProvider, clock: clock)
    #expect(try await authorization.accessToken() == "token1")

    await gate.close()
    clock.advance(by: 3600)
    await mockProvider.setExpiration(.absolute(clock.now.addingTimeInterval(3600)))

    try await withThrowingTaskGroup(of: String.self) { group in
      for _ in 0..<50 {
        group.addTask { try await authorization.accessToken() }
      }
      try await waitUntil { await mockProvider.createSessionCallCount == 2 }
      await gate.open()

      for try await token in group {
        #expect(token == "token2")
      }
    }
    await #expect(mockProvider.createSessionCallCount == 2)

    try await authorization.shutdown()
  }

  @Test func backoffDelayGrowsExponentiallyUpToMaximum() {
    let policy = Authorization.BackoffRetryPolicy()
    #expect(policy.delay(forRetry: 0) == .milliseconds(100))
    #expect(policy.delay(forRetry: 1) == .milliseconds(200))
    #expect(policy.delay(forRetry: 5) == .milliseconds(3200))
    #expect(policy.delay(forRetry: 7) == .milliseconds(3200))
    #expect(policy.delay(forRetry: 1000) == .milliseconds(3200))
  }

  @Test func backoffStopsAfterMaxRetries() async throws {
    var policy = Authorization.BackoffRetryPolicy(
      initialDelay: .microseconds(1), maximumDelay: .microseconds(1), maxRetries: 2)
    #expect(policy.shouldRetry)
    try await policy.beforeRetry()
    #expect(policy.shouldRetry)
    try await policy.beforeRetry()
    #expect(!policy.shouldRetry)
  }

  private func makeAuthorization(provider: Provider, clock: TestClock) -> Authorization {
    Authorization(
      scopes: ["https://www.googleapis.com/auth/cloud-platform"],
      provider: provider,
      eventLoopGroup: MultiThreadedEventLoopGroup.singleton,
      retryPolicy: Authorization.BackoffRetryPolicy(
        initialDelay: .milliseconds(1), maximumDelay: .milliseconds(4), maxRetries: 2),
      now: { clock.now })
  }

  private func waitUntil(_ condition: () async throws -> Bool) async throws {
    for _ in 0..<1000 {
      if try await condition() {
        return
      }
      try await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("Condition was not met in time")
  }

  private final class TestClock: Sendable {

    private let date = Mutex(Date())

    var now: Date {
      date.withLock { $0 }
    }

    func advance(by interval: TimeInterval) {
      date.withLock { $0.addTimeInterval(interval) }
    }
  }

  private actor Gate {

    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
      if isOpen {
        return
      }
      await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
      isOpen = true
      for waiter in waiters {
        waiter.resume()
      }
      waiters = []
    }

    func close() {
      isOpen = false
    }
  }

  private actor MockProvider: Provider {

    struct CreateSessionError: Error {}

    var createSessionCallCount = 0
    var shutdownCallCount = 0
    var isFailing = false
    var failuresBeforeSuccess = 0

    var expiration: Session.Expiration
    let gate: Gate?

    init(expiration: Session.Expiration, gate: Gate? = nil) {
      self.expiration = expiration
      self.gate = gate
    }

    func setFailing(_ isFailing: Bool) {
      self.isFailing = isFailing
    }

    func setFailuresBeforeSuccess(_ failuresBeforeSuccess: Int) {
      self.failuresBeforeSuccess = failuresBeforeSuccess
    }

    func setExpiration(_ expiration: Session.Expiration) {
      self.expiration = expiration
    }

    func createSession(scopes: [Scope], eventLoopGroup: EventLoopGroup) async throws -> Session {
      createSessionCallCount += 1
      let callIndex = createSessionCallCount
      await gate?.wait()
      if isFailing || failuresBeforeSuccess > 0 {
        failuresBeforeSuccess -= 1
        throw CreateSessionError()
      }
      return Session(
        accessToken: "token\(callIndex)",
        expiration: expiration
      )
    }

    func shutdown() async throws {
      shutdownCallCount += 1
    }
  }
}
