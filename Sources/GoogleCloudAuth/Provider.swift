import NIO

public protocol Provider: Sendable {

    func createSession(eventLoopGroup: EventLoopGroup) async throws -> Session
    func shutdown() async throws
}
