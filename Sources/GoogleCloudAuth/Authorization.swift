import Foundation
import Logging
import RetryableTask
import NIO

public actor Authorization {

    public let scopes: [Scope]
    private let provider: Provider
    private let eventLoopGroup: EventLoopGroup
    private let logger = Logger(label: "authorization")

    private var currentSessionTask: Task<Session, Error>?

    public enum Authentication {
        case autoResolve
        case serviceAccount(Data)
    }

    public init(scopes: [Scope], provider: Provider = DefaultProvider.shared, eventLoopGroup: EventLoopGroup) {
        self.scopes = scopes
        self.provider = provider
        self.eventLoopGroup = eventLoopGroup
    }

    public func accessToken(file: String = #fileID, function: String = #function, line: UInt = #line) async throws -> String {
        try await getSession(file: file, function: function, line: line).accessToken
    }

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

    public func shutdown() async throws {
        try await provider.shutdown()
    }
}
