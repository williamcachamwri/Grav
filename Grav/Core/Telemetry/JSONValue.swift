import Foundation

/// Defensive, Sendable JSON value representation capable of decoding arbitrary tool arguments
/// from Antigravity's `transcript.jsonl`, including values serialized as JSON-encoded strings.
public enum JSONValue: Sendable, Equatable, Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .number(Double(int))
        } else if let double = try? container.decode(Double.self) {
            self = .number(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }

    /// Extracts a clean String, automatically unwrapping Antigravity's double-encoded JSON strings
    /// (e.g. `"\"/Users/wica/file.swift\""` -> `"/Users/wica/file.swift"`).
    public var unwrappedString: String? {
        switch self {
        case let .string(raw):
            return Self.unwrapJSONStringLiteral(raw)
        case let .number(value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        case let .bool(value):
            return value ? "true" : "false"
        case .object, .array, .null:
            return nil
        }
    }

    /// Extracts a Bool whether encoded natively (`true`) or as a string (`"true"`).
    public var unwrappedBool: Bool? {
        switch self {
        case let .bool(value):
            return value
        case let .string(raw):
            let trimmed = Self.unwrapJSONStringLiteral(raw).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if trimmed == "true" { return true }
            if trimmed == "false" { return false }
            return nil
        case let .number(value):
            return value != 0
        default:
            return nil
        }
    }

    /// Extracts an Int whether encoded natively (`5000`) or as a string (`"5000"`).
    public var unwrappedInt: Int? {
        switch self {
        case let .number(value):
            return Int(value)
        case let .string(raw):
            let trimmed = Self.unwrapJSONStringLiteral(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(trimmed)
        default:
            return nil
        }
    }

    /// Extracts an array of JSONValues whether encoded natively or as a JSON array string.
    public var unwrappedArray: [JSONValue]? {
        switch self {
        case let .array(values):
            return values
        case let .string(raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("["), let data = trimmed.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode([JSONValue].self, from: data)
        default:
            return nil
        }
    }

    /// Extracts a dictionary of JSONValues whether encoded natively or as a JSON object string.
    public var unwrappedObject: [String: JSONValue]? {
        switch self {
        case let .object(dict):
            return dict
        case let .string(raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode([String: JSONValue].self, from: data)
        default:
            return nil
        }
    }

    /// Unwraps a JSON string literal if the value itself begins and ends with quotes.
    private static func unwrapJSONStringLiteral(_ value: String) -> String {
        guard value.count >= 2, value.first == "\"", value.last == "\"",
              let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(String.self, from: data)
        else {
            return value
        }
        return decoded
    }
}
