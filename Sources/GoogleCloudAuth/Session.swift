import Foundation

/// Represents an authentication session with Google Cloud services.
public struct Session {

    /// The access token used for authentication.
    public let accessToken: String
    
    /// The expiration status of the session.
    public let expiration: Expiration
}

extension Session: Sendable {}

extension Session {

    /// Represents the expiration status of a session.
    public enum Expiration {
        /// The session expires at a specific date and time.
        case absolute(Date)
        /// The session never expires.
        case never
        /// The session is always considered expired.
        case always
    }
}

extension Session.Expiration: Sendable {}

extension Session.Expiration: Equatable {}

extension Session {

    /// Indicates whether the session is currently expired.
    public var isExpired: Bool {
        switch expiration {
        case .absolute(let date):
            return date < Date()
        case .never:
            return false
        case .always:
            return true
        }
    }
}
