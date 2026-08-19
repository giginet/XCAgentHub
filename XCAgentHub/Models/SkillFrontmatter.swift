import Foundation

/// The YAML frontmatter block at the top of a SKILL.md. `name`,
/// `description`, and `allowed-tools` have dedicated form fields; anything
/// else is an arbitrary key/value pair.
struct SkillFrontmatter: Sendable {
    static let nameKey = "name"
    static let descriptionKey = "description"
    static let allowedToolsKey = "allowed-tools"

    /// Keys with a dedicated field, so an extra key/value row cannot emit a
    /// duplicate of one.
    static let reservedKeys: Set<String> = [nameKey, descriptionKey, allowedToolsKey]

    var name: String = ""
    var summary: String = ""
    var allowedTools: [String] = []
    var extraFields: [(key: String, value: String)] = []

    /// The `---` delimited block. `name` is always written; the other fields
    /// are omitted when empty, and extra rows with a blank or reserved key
    /// are dropped.
    func rendered() -> String {
        var lines = ["---", "\(Self.nameKey): \(Self.scalar(name))"]

        let description = Self.singleLine(summary)
        if !description.isEmpty {
            lines.append("\(Self.descriptionKey): \(Self.scalar(description))")
        }

        let tools = allowedTools
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !tools.isEmpty {
            lines.append("\(Self.allowedToolsKey): \(tools.joined(separator: ", "))")
        }

        var usedKeys = Self.reservedKeys
        for field in extraFields {
            let key = field.key.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, usedKeys.insert(key).inserted else { continue }
            lines.append("\(key): \(Self.scalar(Self.singleLine(field.value)))")
        }

        lines.append("---")
        return lines.joined(separator: "\n")
    }

    /// The parser in `SkillStore` reads one `key: value` per line, so values
    /// are folded onto a single line.
    private static func singleLine(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Double-quotes a value that plain YAML would misread, such as one
    /// containing `: ` or starting with an indicator character.
    private static func scalar(_ value: String) -> String {
        let indicators = "-?:,[]{}#&*!|>'\"%@`"
        let needsQuotes = value.isEmpty
            || value.contains(": ")
            || value.hasSuffix(":")
            || value.contains(" #")
            || indicators.contains(value.first ?? "a")
        guard needsQuotes else { return value }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
