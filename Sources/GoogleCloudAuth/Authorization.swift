import Foundation
import Logging
import NIO
import RetryableTask
import Tracing

/// An actor that manages authorization and session creation for Google Cloud services.
public actor Authorization {

  /// The scopes required for authorization.
  public let scopes: [Scope]

  private let provider: Provider
  private let eventLoopGroup: EventLoopGroup
  private let retryPolicy: RetryPolicy
  private let now: @Sendable () -> Date
  private let logger = Logger(label: "authorization")

  private var cachedSession: CachedSession?
  private var refreshTask: Task<Session, Error>?

  /// Initializes a new Authorization instance.
  /// - Parameters:
  ///   - scopes: An array of scopes required for authorization.
  ///   - provider: The provider to use for creating sessions. Defaults to `DefaultProvider.shared`.
  ///   - eventLoopGroup: The event loop group to use for asynchronous operations.
  public init(
    scopes: [Scope], provider: Provider = DefaultProvider.shared, eventLoopGroup: EventLoopGroup
  ) {
    self.init(
      scopes: scopes, provider: provider, eventLoopGroup: eventLoopGroup,
      retryPolicy: BackoffRetryPolicy(), now: { Date() })
  }

  init(
    scopes: [Scope],
    provider: Provider,
    eventLoopGroup: EventLoopGroup,
    retryPolicy: RetryPolicy,
    now: @escaping @Sendable () -> Date
  ) {
    self.scopes = scopes
    self.provider = provider
    self.eventLoopGroup = eventLoopGroup
    self.retryPolicy = retryPolicy
    self.now = now
  }

  /// Retrieves an access token for the authorized session.
  /// - Parameters:
  ///   - file: The file where this method is called. Defaults to the current file.
  ///   - function: The function where this method is called. Defaults to the current function.
  ///   - line: The line number where this method is called. Defaults to the current line.
  /// - Returns: A string representing the access token.
  /// - Throws: An error if the access token cannot be retrieved.
  public func accessToken(file: String = #fileID, function: String = #function, line: UInt = #line)
    async throws -> String
  {
    try await getSession(file: file, function: function, line: line).accessToken
  }

  /// Retrieves or creates a new authorized session.
  ///
  /// Sessions are refreshed in the background shortly before they expire, while the current
  /// session keeps being returned. Concurrent callers share a single in-progress refresh, and
  /// failed refreshes are not cached.
  /// - Parameters:
  ///   - file: The file where this method is called. Defaults to the current file.
  ///   - function: The function where this method is called. Defaults to the current function.
  ///   - line: The line number where this method is called. Defaults to the current line.
  /// - Returns: An authorized `Session` instance.
  /// - Throws: An error if the session cannot be created or retrieved.
  public func getSession(file: String = #fileID, function: String = #function, line: UInt = #line)
    async throws -> Session
  {
    let now = self.now()
    if let cachedSession, cachedSession.isUsable(at: now) {
      if cachedSession.needsRefresh(at: now) {
        _ = refresh(file: file, function: function, line: line)
      }
      return cachedSession.session
    }
    return try await refresh(file: file, function: function, line: line).value
  }

  /// Sessions are refreshed this long before they expire, so tokens don't expire in flight.
  static let refreshMargin: TimeInterval = 4 * 60

  /// Sessions expiring within this interval are not returned without waiting for a refresh.
  static let expiryMargin: TimeInterval = 10

  /// Returns the in-progress refresh, or starts one if none is running.
  private func refresh(file: String, function: String, line: UInt) -> Task<Session, Error> {
    if let refreshTask {
      return refreshTask
    }
    let task = Task { [scopes, provider, eventLoopGroup, retryPolicy, logger] in
      // Only one refresh runs at a time and this body runs after `refreshTask` is assigned.
      defer { refreshTask = nil }
      let fetchDate = now()
      let session: Session
      do {
        session = try await withRetryableTask(
          policy: retryPolicy,
          logger: logger,
          operation: {
            try await withSpan("authorization.create-session", ofKind: .client) { _ in
              try await provider.createSession(scopes: scopes, eventLoopGroup: eventLoopGroup)
            }
          }, file: file, function: function, line: line)
      } catch {
        logger.error(
          "Failed to create session: \(error)", file: file, function: function, line: line)
        throw error
      }
      cachedSession = CachedSession(session: session, fetchDate: fetchDate)
      return session
    }
    refreshTask = task
    return task
  }

  /// Shuts down the authorization provider.
  ///
  /// `DefaultProvider.shared` is shared by all users in the process and is not shut down. Call
  /// `DefaultProvider.shared.shutdown()` directly to release its resources.
  /// - Throws: An error if the shutdown process fails.
  public func shutdown() async throws {
    refreshTask?.cancel()
    if provider is DefaultProvider {
      return
    }
    try await provider.shutdown()
  }
}

extension Authorization {

  /// A session together with the dates it should be refreshed and stop being used.
  struct CachedSession: Sendable {

    let session: Session
    let refreshDate: Date
    let expiryDate: Date

    /// Margins are capped relative to the session's lifetime, so sessions with a lifetime shorter
    /// than the margins are still reused instead of being fetched on every call.
    init(session: Session, fetchDate: Date) {
      self.session = session
      switch session.expiration {
      case .absolute(let date):
        let lifetime = max(date.timeIntervalSince(fetchDate), 0)
        refreshDate = date.addingTimeInterval(-min(Authorization.refreshMargin, lifetime / 2))
        expiryDate = date.addingTimeInterval(-min(Authorization.expiryMargin, lifetime / 4))
      case .never:
        refreshDate = .distantFuture
        expiryDate = .distantFuture
      case .always:
        refreshDate = .distantPast
        expiryDate = .distantPast
      }
    }

    func isUsable(at date: Date) -> Bool {
      date < expiryDate
    }

    func needsRefresh(at date: Date) -> Bool {
      date >= refreshDate
    }
  }
}
