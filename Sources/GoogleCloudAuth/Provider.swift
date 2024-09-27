import NIO

/// A protocol that defines the interface for authentication providers.
///
/// Implementations of this protocol are responsible for creating a authentication
/// session. No need to handle checking if the session is expired.
public protocol Provider: Sendable {

    /// Creates a new authentication session with the specified scopes.
    ///
    /// - Parameters:
    ///   - scopes: An array of `Scope` objects representing the access scopes required for the session.
    ///   - eventLoopGroup: The `EventLoopGroup` to be used for asynchronous operations.
    ///
    /// - Returns: A `Session` object representing the authenticated session.
    ///
    /// - Throws: An error if the session creation fails.
    func createSession(scopes: [Scope], eventLoopGroup: EventLoopGroup) async throws -> Session

    /// Shuts down the provider and releases any resources.
    ///
    /// This method should be called when the provider is no longer needed to ensure
    /// proper cleanup of resources.
    ///
    /// - Throws: An error if the shutdown process encounters any issues.
    func shutdown() async throws
}
