import Foundation
import TOML

/// A dynamic TOML value that round-trips documents without a fixed schema.
/// swift-toml only offers Codable interfaces, so this type stands in for
/// "any value" and lets stores rewrite one table while preserving the values
/// of every other key in the document.
enum TOMLAnyValue: Codable, Hashable {
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case date(Date)
    case localDateTime(LocalDateTime)
    case localDate(LocalDate)
    case localTime(LocalTime)
    case array([TOMLAnyValue])
    case table([String: TOMLAnyValue])

    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    init(from decoder: any Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var table: [String: TOMLAnyValue] = [:]
            for key in keyed.allKeys {
                table[key.stringValue] = try keyed.decode(TOMLAnyValue.self, forKey: key)
            }
            self = .table(table)
            return
        }
        if var unkeyed = try? decoder.unkeyedContainer() {
            var values: [TOMLAnyValue] = []
            while !unkeyed.isAtEnd {
                values.append(try unkeyed.decode(TOMLAnyValue.self))
            }
            self = .array(values)
            return
        }
        let single = try decoder.singleValueContainer()
        if let value = try? single.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? single.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? single.decode(Double.self) {
            self = .double(value)
        } else if let value = try? single.decode(String.self) {
            self = .string(value)
        } else if let value = try? single.decode(Date.self) {
            self = .date(value)
        } else if let value = try? single.decode(LocalDateTime.self) {
            self = .localDateTime(value)
        } else if let value = try? single.decode(LocalDate.self) {
            self = .localDate(value)
        } else if let value = try? single.decode(LocalTime.self) {
            self = .localTime(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: single,
                debugDescription: "Unsupported TOML value"
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .table(let table):
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, value) in table {
                try container.encode(value, forKey: DynamicCodingKey(stringValue: key)!)
            }
        case .array(let values):
            var container = encoder.unkeyedContainer()
            for value in values {
                try container.encode(value)
            }
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .int(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .double(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .date(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .localDateTime(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .localDate(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .localTime(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        }
    }

    // MARK: - Convenience accessors

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var arrayValue: [TOMLAnyValue]? {
        if case .array(let values) = self { return values }
        return nil
    }

    var tableValue: [String: TOMLAnyValue]? {
        if case .table(let table) = self { return table }
        return nil
    }
}
