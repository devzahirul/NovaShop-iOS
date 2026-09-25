/// A phantom-typed identifier. `Product.ID` and `Category.ID` are both strings on the wire but
/// can never be mixed up at compile time — a whole class of "passed the wrong id" bugs disappears.
public struct Tagged<Tag, RawValue: Hashable & Sendable & Codable>: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: RawValue

    public init(rawValue: RawValue) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: RawValue) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(RawValue.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension Tagged: ExpressibleByStringLiteral, ExpressibleByUnicodeScalarLiteral,
    ExpressibleByExtendedGraphemeClusterLiteral where RawValue == String {
    public init(stringLiteral value: String) {
        rawValue = value
    }
}

extension Tagged: CustomStringConvertible {
    public var description: String {
        "\(rawValue)"
    }
}
