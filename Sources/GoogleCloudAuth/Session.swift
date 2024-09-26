import Foundation

public struct Session {

    public let accessToken: String
    public let expiration: Expiration
}

extension Session: Sendable {}

extension Session {

    public enum Expiration {
        case absolute(Date)
        case never
        case always
    }
}

extension Session.Expiration: Sendable {}

extension Session.Expiration: Equatable {}

extension Session {

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
