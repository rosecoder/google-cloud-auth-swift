import NIO

public protocol Provider: Sendable {

    func createSession(scopes: [Scope], eventLoopGroup: EventLoopGroup) async throws -> Session
    func shutdown() async throws
}
