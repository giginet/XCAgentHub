import Foundation
import Testing
@testable import XCAgentHub

@Suite("SkillFrontmatter")
struct SkillFrontmatterTests {
@Suite("Rendering")
struct Rendering {
        @Test func rendersOnlyTheFieldsThatHaveValues() {
            let frontmatter = SkillFrontmatter(name: "my-skill")

            #expect(frontmatter.rendered() == """
            ---
            name: my-skill
            ---
            """)
        }

        @Test func rendersDescriptionAllowedToolsAndExtraFields() {
            let frontmatter = SkillFrontmatter(
                name: "my-skill",
                summary: "Does a thing",
                allowedTools: ["Bash", " Read ", ""],
                extraFields: [(key: "license", value: "MIT")]
            )

            #expect(frontmatter.rendered() == """
            ---
            name: my-skill
            description: Does a thing
            allowed-tools: Bash, Read
            license: MIT
            ---
            """)
        }

        @Test func skipsBlankAndReservedExtraKeys() {
            let frontmatter = SkillFrontmatter(
                name: "my-skill",
                summary: "Does a thing",
                extraFields: [
                    (key: "  ", value: "ignored"),
                    (key: "description", value: "duplicate"),
                    (key: "license", value: "MIT"),
                    (key: "license", value: "Apache-2.0"),
                ]
            )
            let values = SkillStore.parseFrontmatter(frontmatter.rendered())

            #expect(values["description"] == "Does a thing")
            #expect(values["license"] == "MIT")
            #expect(values.count == 3)
        }

        @Test func foldsMultiLineValuesAndQuotesAmbiguousOnes() {
            let frontmatter = SkillFrontmatter(
                name: "my-skill",
                summary: "First line\nsecond line",
                extraFields: [(key: "note", value: "key: value")]
            )
            let rendered = frontmatter.rendered()

            #expect(rendered.contains("description: First line second line"))
            #expect(rendered.contains("note: \"key: value\""))
            #expect(SkillStore.parseFrontmatter(rendered)["note"] == "key: value")
        }
}

@Suite("Parsing")
struct Parsing {
        @Test func splitsFrontmatterFromBody() throws {
            let parsed = try #require(SkillFrontmatter.parse("""
            ---
            name: my-skill
            description: Does a thing
            allowed-tools: Bash, Read
            license: MIT
            ---

            # Heading

            Body text.
            """))

            #expect(parsed.frontmatter.name == "my-skill")
            #expect(parsed.frontmatter.summary == "Does a thing")
            #expect(parsed.frontmatter.allowedTools == ["Bash", "Read"])
            #expect(parsed.frontmatter.extraFields.map(\.key) == ["license"])
            #expect(parsed.frontmatter.extraFields.first?.value == "MIT")
            #expect(parsed.body == "# Heading\n\nBody text.")
        }

        @Test func readsBlockAndFlowToolLists() throws {
            let block = try #require(SkillFrontmatter.parse("""
            ---
            name: my-skill
            allowed-tools:
              - Bash
              - "Read"
            ---
            Body
            """))
            #expect(block.frontmatter.allowedTools == ["Bash", "Read"])

            let flow = try #require(SkillFrontmatter.parse("""
            ---
            name: my-skill
            allowed-tools: [Bash, Read]
            ---
            Body
            """))
            #expect(flow.frontmatter.allowedTools == ["Bash", "Read"])
        }

        @Test func unquotesValuesAndSurvivesARoundTrip() throws {
            let original = """
            ---
            name: my-skill
            description: "key: value, quoted"
            ---
            Body
            """
            let parsed = try #require(SkillFrontmatter.parse(original))
            #expect(parsed.frontmatter.summary == "key: value, quoted")

            let rendered = "\(parsed.frontmatter.rendered())\n\n\(parsed.body)"
            let reparsed = try #require(SkillFrontmatter.parse(rendered))
            #expect(reparsed.frontmatter.summary == parsed.frontmatter.summary)
            #expect(reparsed.body == parsed.body)
        }

        @Test(arguments: [
            // No frontmatter at all.
            "# Just Markdown",
            // Unterminated frontmatter.
            "---\nname: my-skill\n",
            // A comment the form has nowhere to keep.
            "---\n# why this exists\nname: my-skill\n---\nBody",
            // A block scalar.
            "---\nname: my-skill\ndescription: |\n  line one\n  line two\n---\nBody",
            // A nested map.
            "---\nname: my-skill\nmetadata:\n  type: reference\n---\nBody",
            // A flow sequence under a key with no dedicated field.
            "---\nname: my-skill\ntags: [a, b]\n---\nBody",
        ])
        func refusesYAMLItWouldDestroy(content: String) {
            #expect(SkillFrontmatter.parse(content) == nil)
        }
}
}
