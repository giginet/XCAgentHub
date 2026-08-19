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

extension SkillFrontmatter {
    /// A SKILL.md split into the frontmatter this form can edit and the
    /// Markdown body below it.
    ///
    /// Returns nil when the file has no frontmatter, or carries YAML that
    /// rendering it back out would destroy — comments, block scalars, nested
    /// maps. The caller falls back to editing the raw text in that case,
    /// rather than quietly dropping what it could not represent.
    static func parse(_ content: String) -> (frontmatter: SkillFrontmatter, body: String)? {
        let lines = content.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        guard let closing = lines.dropFirst().firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "---"
        }) else { return nil }

        var frontmatter = SkillFrontmatter()
        var index = 1
        while index < closing {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }
            // A comment, or a line indented under the previous key: both carry
            // meaning this form has nowhere to put.
            guard !trimmed.hasPrefix("#"), line.first?.isWhitespace != true else { return nil }
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return nil }
            let rawValue = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)

            if rawValue.isEmpty {
                // The only multi-line shape worth understanding is a block
                // list of tools; anything else is a nested map.
                let list = blockList(in: lines, from: index + 1, before: closing)
                guard key == allowedToolsKey, !list.items.isEmpty else { return nil }
                frontmatter.allowedTools = list.items
                index = list.next
                continue
            }
            guard !rawValue.hasPrefix("|"), !rawValue.hasPrefix(">"), !rawValue.hasPrefix("{") else { return nil }
            guard !rawValue.hasPrefix("[") || key == allowedToolsKey else { return nil }

            switch key {
            case nameKey:
                frontmatter.name = unquote(rawValue)
            case descriptionKey:
                frontmatter.summary = unquote(rawValue)
            case allowedToolsKey:
                frontmatter.allowedTools = splitTools(rawValue)
            default:
                frontmatter.extraFields.append((key: key, value: unquote(rawValue)))
            }
            index += 1
        }

        var body = lines[(closing + 1)...].joined(separator: "\n")
        while body.hasPrefix("\n") {
            body.removeFirst()
        }
        return (frontmatter, body)
    }

    /// Reads `- item` lines following a key that had no inline value, and
    /// reports the line the block ends on.
    private static func blockList(
        in lines: [String],
        from start: Int,
        before end: Int
    ) -> (items: [String], next: Int) {
        var items: [String] = []
        var index = start
        while index < end {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }
            guard trimmed.hasPrefix("-") else { break }
            let item = unquote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
            if !item.isEmpty {
                items.append(item)
            }
            index += 1
        }
        return (items, index)
    }

    /// Accepts both the comma-separated form this app writes and the flow
    /// sequence `[Bash, Read]`.
    private static func splitTools(_ rawValue: String) -> [String] {
        var value = rawValue
        if value.hasPrefix("["), value.hasSuffix("]") {
            value = String(value.dropFirst().dropLast())
        }
        return value
            .split(separator: ",")
            .map { unquote($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, let last = value.last,
              first == last, first == "\"" || first == "'"
        else { return value }
        let inner = String(value.dropFirst().dropLast())
        guard first == "\"" else { return inner }
        return inner
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
