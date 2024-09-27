import Foundation
import Logging
import RetryableTask
import NIO

/// An actor that manages authorization and session creation for Google Cloud services.
public actor Authorization {

    /// The scopes required for authorization.
    public let scopes: [Scope]

    private let provider: Provider
    private let eventLoopGroup: EventLoopGroup
    private let logger = Logger(label: "authorization")

    private var currentSessionTask: Task<Session, Error>?

    /// Initializes a new Authorization instance.
    /// - Parameters:
    ///   - scopes: An array of scopes required for authorization.
    ///   - provider: The provider to use for creating sessions. Defaults to `DefaultProvider.shared`.
    ///   - eventLoopGroup: The event loop group to use for asynchronous operations.
    public init(scopes: [Scope], provider: Provider = DefaultProvider.shared, eventLoopGroup: EventLoopGroup) {
        self.scopes = scopes
        self.provider = provider
        self.eventLoopGroup = eventLoopGroup
    }

    /// Retrieves an access token for the authorized session.
    /// - Parameters:
    ///   - file: The file where this method is called. Defaults to the current file.
    ///   - function: The function where this method is called. Defaults to the current function.
    ///   - line: The line number where this method is called. Defaults to the current line.
    /// - Returns: A string representing the access token.
    /// - Throws: An error if the access token cannot be retrieved.
    public func accessToken(file: String = #fileID, function: String = #function, line: UInt = #line) async throws -> String {
        try await getSession(file: file, function: function, line: line).accessToken
    }

    /// Retrieves or creates a new authorized session.
    /// - Parameters:
    ///   - file: The file where this method is called. Defaults to the current file.
    ///   - function: The function where this method is called. Defaults to the current function.
    ///   - line: The line number where this method is called. Defaults to the current line.
    /// - Returns: An authorized `Session` instance.
    /// - Throws: An error if the session cannot be created or retrieved.
    public func getSession(file: String = #fileID, function: String = #function, line: UInt = #line) async throws -> Session {
        if let currentSessionTask {
            let session = try await currentSessionTask.value
            if session.isExpired {
                self.currentSessionTask = nil
                return try await getSession(file: file, function: function, line: line)
            }
            return session
        }
        let task = Task { [scopes, provider, eventLoopGroup] in
            try await withRetryableTask(logger: logger, operation: {
                try await provider.createSession(scopes: scopes, eventLoopGroup: eventLoopGroup)
            }, file: file, function: function, line: line)
        }
        self.currentSessionTask = task

        return try await task.value
    }

    /// Shuts down the authorization provider.
    /// - Throws: An error if the shutdown process fails.
    public func shutdown() async throws {
        try await provider.shutdown()
    }
}
