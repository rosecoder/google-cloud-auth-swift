public struct Scope {

    public let rawValue: String
}

extension Scope: Sendable {}

extension Scope: Hashable {}

extension Scope: Equatable {}

extension Scope: ExpressibleByStringLiteral {

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}
