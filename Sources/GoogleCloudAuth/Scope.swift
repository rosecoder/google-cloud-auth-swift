/// Represents a Google Cloud API scope.
/// A scope is a string that defines the level of access requested for a particular API.
public struct Scope {

    /// The raw string value of the scope.
    public let rawValue: String
}

extension Scope: Sendable {}

extension Scope: Hashable {}

extension Scope: Equatable {}

extension Scope: ExpressibleByStringLiteral {

    /// Creates a new Scope instance from a string literal.
    ///
    /// - Parameter value: The string literal to use as the scope's raw value.
    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}
