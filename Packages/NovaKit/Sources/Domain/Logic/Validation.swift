import Foundation

/// Form validation rules. Pure and synchronous so forms validate on every keystroke for free and
/// every rule is covered by a table-driven test.
public enum Validation {
    public enum Failure: Error, Equatable, Sendable {
        case required(String)
        case invalidEmail
        case passwordTooShort(minimum: Int)
        case invalidCardNumber
        case invalidExpiry
        case expiredCard
        case invalidCVV
        case invalidPostalCode

        public var message: String {
            switch self {
            case let .required(field): "\(field) is required"
            case .invalidEmail: "Enter a valid email address"
            case let .passwordTooShort(minimum): "Use at least \(minimum) characters"
            case .invalidCardNumber: "Check your card number"
            case .invalidExpiry: "Use MM/YY"
            case .expiredCard: "This card has expired"
            case .invalidCVV: "Check your security code"
            case .invalidPostalCode: "Enter a 5-digit ZIP code"
            }
        }
    }

    public static let minimumPasswordLength = 8

    public static func email(_ value: String) -> Failure? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .required("Email") }
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
              !parts[1].hasPrefix("."), !parts[1].hasSuffix("."), !trimmed.contains(" ")
        else { return .invalidEmail }
        return nil
    }

    public static func password(_ value: String) -> Failure? {
        guard !value.isEmpty else { return .required("Password") }
        return value.count < minimumPasswordLength ? .passwordTooShort(minimum: minimumPasswordLength) : nil
    }

    public static func required(_ value: String, field: String) -> Failure? {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .required(field) : nil
    }

    /// US ZIP (`12345`) or ZIP+4 (`12345-6789` / `123456789`).
    public static func postalCode(_ value: String) -> Failure? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .required("ZIP code") }
        let digits = trimmed.filter(\.isNumber)
        let onlyDigitsAndHyphen = trimmed.allSatisfy { $0.isNumber || $0 == "-" }
        return onlyDigitsAndHyphen && (digits.count == 5 || digits.count == 9) ? nil : .invalidPostalCode
    }

    /// USPS codes for the 50 states + DC.
    public static var usStates: [String] {
        USState.all.map(\.code)
    }

    // MARK: Cards

    public static func cardNumber(_ value: String) -> Failure? {
        let digits = value.filter(\.isNumber)
        guard !digits.isEmpty else { return .required("Card number") }
        guard (13 ... 19).contains(digits.count), luhn(digits) else { return .invalidCardNumber }
        return nil
    }

    /// Validates `MM/YY` against the injected `now` (never `Date()` inside logic — tests control time).
    public static func expiry(_ value: String, now: Date, calendar: Calendar = .init(identifier: .gregorian)) -> Failure? {
        let parts = value.split(separator: "/")
        guard parts.count == 2, let month = Int(parts[0]), let year = Int(parts[1]),
              (1 ... 12).contains(month), parts[1].count == 2
        else { return .invalidExpiry }
        let current = calendar.dateComponents([.year, .month], from: now)
        let fullYear = 2000 + year
        guard let currentYear = current.year, let currentMonth = current.month else { return .invalidExpiry }
        if fullYear < currentYear || (fullYear == currentYear && month < currentMonth) {
            return .expiredCard
        }
        return nil
    }

    public static func cvv(_ value: String, brand: CardBrand) -> Failure? {
        let expected = brand == .amex ? 4 : 3
        return value.count == expected && value.allSatisfy(\.isNumber) ? nil : .invalidCVV
    }

    public static func brand(forCardNumber value: String) -> CardBrand {
        let digits = value.filter(\.isNumber)
        if digits.hasPrefix("4") {
            return .visa
        }
        if let two = Int(digits.prefix(2)), (51 ... 55).contains(two) {
            return .mastercard
        }
        if let four = Int(digits.prefix(4)), (2221 ... 2720).contains(four) {
            return .mastercard
        }
        if digits.hasPrefix("34") || digits.hasPrefix("37") {
            return .amex
        }
        if digits.hasPrefix("6011") || digits.hasPrefix("65") {
            return .discover
        }
        return .unknown
    }

    /// Luhn mod-10 checksum.
    public static func luhn(_ digits: String) -> Bool {
        var sum = 0
        for (index, character) in digits.reversed().enumerated() {
            guard var digit = character.wholeNumberValue else { return false }
            if index.isMultiple(of: 2) == false {
                digit *= 2
                if digit > 9 {
                    digit -= 9
                }
            }
            sum += digit
        }
        return sum.isMultiple(of: 10)
    }
}

/// Input formatting helpers for the card form ("4242424242424242" → "4242 4242 4242 4242").
public enum CardFormatter {
    public static func formatNumber(_ raw: String) -> String {
        let digits = String(raw.filter(\.isNumber).prefix(19))
        return stride(from: 0, to: digits.count, by: 4).map { offset -> String in
            let start = digits.index(digits.startIndex, offsetBy: offset)
            let end = digits.index(start, offsetBy: 4, limitedBy: digits.endIndex) ?? digits.endIndex
            return String(digits[start ..< end])
        }.joined(separator: " ")
    }

    public static func formatExpiry(_ raw: String) -> String {
        let digits = String(raw.filter(\.isNumber).prefix(4))
        guard digits.count > 2 else { return digits }
        return "\(digits.prefix(2))/\(digits.dropFirst(2))"
    }
}

/// A US state / district, for address entry. Full names make the picker searchable ("jersey" → NJ).
public struct USState: Identifiable, Hashable, Sendable {
    public let code: String
    public let name: String
    public var id: String {
        code
    }

    public static func named(_ code: String) -> USState? {
        all.first { $0.code == code }
    }

    public static func search(_ text: String) -> [USState] {
        let term = text.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(term) || $0.code.caseInsensitiveCompare(term) == .orderedSame }
    }

    public static let all: [USState] = [
        ("AL", "Alabama"), ("AK", "Alaska"), ("AZ", "Arizona"), ("AR", "Arkansas"), ("CA", "California"),
        ("CO", "Colorado"), ("CT", "Connecticut"), ("DE", "Delaware"), ("DC", "District of Columbia"),
        ("FL", "Florida"), ("GA", "Georgia"), ("HI", "Hawaii"), ("ID", "Idaho"), ("IL", "Illinois"),
        ("IN", "Indiana"), ("IA", "Iowa"), ("KS", "Kansas"), ("KY", "Kentucky"), ("LA", "Louisiana"),
        ("ME", "Maine"), ("MD", "Maryland"), ("MA", "Massachusetts"), ("MI", "Michigan"), ("MN", "Minnesota"),
        ("MS", "Mississippi"), ("MO", "Missouri"), ("MT", "Montana"), ("NE", "Nebraska"), ("NV", "Nevada"),
        ("NH", "New Hampshire"), ("NJ", "New Jersey"), ("NM", "New Mexico"), ("NY", "New York"),
        ("NC", "North Carolina"), ("ND", "North Dakota"), ("OH", "Ohio"), ("OK", "Oklahoma"), ("OR", "Oregon"),
        ("PA", "Pennsylvania"), ("RI", "Rhode Island"), ("SC", "South Carolina"), ("SD", "South Dakota"),
        ("TN", "Tennessee"), ("TX", "Texas"), ("UT", "Utah"), ("VT", "Vermont"), ("VA", "Virginia"),
        ("WA", "Washington"), ("WV", "West Virginia"), ("WI", "Wisconsin"), ("WY", "Wyoming"),
    ].map { USState(code: $0.0, name: $0.1) }
}
