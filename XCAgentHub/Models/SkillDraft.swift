import Foundation

/// A SKILL.md as the form edits it: the frontmatter split into fields and
/// rows, plus the Markdown body. Rows carry an id so a table cell keeps
/// focus while its text changes.
struct SkillDraft {
    struct ToolRow: Identifiable {
        let id = UUID()
        var name: String
    }

    struct FieldRow: Identifiable {
        let id = UUID()
        var key: String
        var value: String
    }

    var name = ""
    var summary = ""
    /// Both tables keep one blank row so there is somewhere to type without
    /// hitting Add first. Blank rows are dropped when rendering.
    var toolRows: [ToolRow] = [ToolRow(name: "")]
    var fieldRows: [FieldRow] = [FieldRow(key: "", value: "")]
    var instructions = ""

    init() {}

    init(frontmatter: SkillFrontmatter, body: String) {
        name = frontmatter.name
        summary = frontmatter.summary
        toolRows = frontmatter.allowedTools.map { ToolRow(name: $0) }
        fieldRows = frontmatter.extraFields.map { FieldRow(key: $0.key, value: $0.value) }
        instructions = body
        if toolRows.isEmpty {
            toolRows = [ToolRow(name: "")]
        }
        if fieldRows.isEmpty {
            fieldRows = [FieldRow(key: "", value: "")]
        }
    }

    var frontmatter: SkillFrontmatter {
        SkillFrontmatter(
            name: name,
            summary: summary,
            allowedTools: toolRows.map(\.name),
            extraFields: fieldRows.map { (key: $0.key, value: $0.value) }
        )
    }

    /// The whole file: frontmatter block, blank line, body.
    var content: String {
        "\(frontmatter.rendered())\n\n\(instructions)"
    }
}
