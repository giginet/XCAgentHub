import Foundation
import Testing
@testable import AgentHub

@Suite("SkillStore")
struct SkillStoreTests {
@Suite("Listing")
struct Listing {
        @Test func listSkipsHiddenAndInvalidDirectories() throws {
            let directory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = makeSkillStore(in: directory)
            let skillsDir = store.skillsDirectoryURL

            try writeSkill(named: "good-skill", content: """
            ---
            name: good-skill
            description: "Does good things"
            ---

            # Body
            """, in: skillsDir)
            // Hidden directory (like Codex's .system) must be skipped.
            try writeSkill(named: ".system", content: "---\nname: sys\n---\n", in: skillsDir)
            // A directory without SKILL.md must be skipped.
            try FileManager.default.createDirectory(
                at: skillsDir.appending(path: "not-a-skill"),
                withIntermediateDirectories: true
            )
            // A plain file must be skipped.
            try "hi".write(to: skillsDir.appending(path: "note.txt"), atomically: true, encoding: .utf8)

            let skills = try store.list()
            #expect(skills.count == 1)
            let skill = try #require(skills.first)
            #expect(skill.name == "good-skill")
            #expect(skill.summary == "Does good things")
            #expect(skill.directoryName == "good-skill")
        }

        @Test func listReturnsEmptyForMissingDirectory() throws {
            let directory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            #expect(try makeSkillStore(in: directory).list().isEmpty)
        }
}

@Suite("Creating")
struct Creating {
        @Test func createSanitizesNameAndAddsFrontmatter() throws {
            let directory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = makeSkillStore(in: directory)

            let skill = try store.create(named: "My Cool Skill", content: "Do the thing.")
            #expect(skill.directoryName == "my-cool-skill")
            let written = try String(contentsOf: skill.skillFileURL, encoding: .utf8)
            #expect(written.hasPrefix("---\nname: my-cool-skill\n---"))
            #expect(written.contains("Do the thing."))

            // Creating the same skill again fails.
            #expect(throws: SkillStoreError.self) {
                try store.create(named: "my cool skill", content: "again")
            }
            // An unusable name fails.
            #expect(throws: SkillStoreError.self) {
                try store.create(named: "!!!", content: "x")
            }
        }

        @Test func createKeepsExistingFrontmatter() throws {
            let directory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = makeSkillStore(in: directory)

            let original = "---\nname: custom\ndescription: mine\n---\n\nBody"
            let skill = try store.create(named: "custom", content: original)
            #expect(try String(contentsOf: skill.skillFileURL, encoding: .utf8) == original)
            #expect(skill.name == "custom")
            #expect(skill.summary == "mine")
        }
}

@Suite("Importing")
struct Importing {
        @Test func importCopiesWholeDirectory() throws {
            let directory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = makeSkillStore(in: directory)

            // Source skill with a nested asset.
            let source = directory.appending(path: "source/tool-skill")
            try FileManager.default.createDirectory(
                at: source.appending(path: "assets"),
                withIntermediateDirectories: true
            )
            try "---\nname: tool-skill\n---\n".write(
                to: source.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
            try "asset".write(
                to: source.appending(path: "assets/data.txt"), atomically: true, encoding: .utf8)

            let skill = try store.importSkill(from: source)
            #expect(skill.directoryName == "tool-skill")
            #expect(FileManager.default.fileExists(
                atPath: store.skillsDirectoryURL.appending(path: "tool-skill/assets/data.txt").path))

            // Importing the same folder again fails.
            #expect(throws: SkillStoreError.self) {
                try store.importSkill(from: source)
            }
            // A folder without SKILL.md fails.
            let empty = directory.appending(path: "source/empty")
            try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
            #expect(throws: SkillStoreError.self) {
                try store.importSkill(from: empty)
            }
        }

        @Test func importMaterializesSymlinkedFiles() throws {
            let directory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }

            // A skill laid out the way a dotfiles repo does it: SKILL.md and a
            // reference file are relative symlinks into a sibling folder.
            let shared = directory.appending(path: "shared")
            try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
            try "---\nname: linked-skill\ndescription: Linked\n---\nBody"
                .write(to: shared.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
            try "reference".write(to: shared.appending(path: "REFERENCE.md"), atomically: true, encoding: .utf8)

            let source = directory.appending(path: "linked-skill")
            try FileManager.default.createDirectory(
                at: source.appending(path: "references"),
                withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(
                atPath: source.appending(path: "SKILL.md").path,
                withDestinationPath: "../shared/SKILL.md"
            )
            try FileManager.default.createSymbolicLink(
                atPath: source.appending(path: "references/REFERENCE.md").path,
                withDestinationPath: "../../shared/REFERENCE.md"
            )

            let skillsDirectory = directory.appending(path: "skills")
            let store = SkillStore(skillsDirectoryURL: skillsDirectory, agent: .claudeCode)
            let imported = try store.importSkill(from: source)

            // The copies are real files, not links that broke on the way over.
            let copiedSkillFile = imported.skillFileURL
            let type = try FileManager.default.attributesOfItem(atPath: copiedSkillFile.path)[.type] as? FileAttributeType
            #expect(type == .typeRegular)
            #expect(try String(contentsOf: copiedSkillFile, encoding: .utf8).contains("Body"))
            #expect(try String(
                contentsOf: imported.directoryURL.appending(path: "references/REFERENCE.md"),
                encoding: .utf8
            ) == "reference")

            let listed = try store.list()
            #expect(listed.map(\.name) == ["linked-skill"])
            #expect(listed.first?.summary == "Linked")
        }

        @Test func importRejectsAFolderWhoseSkillFileIsABrokenLink() throws {
            let directory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }

            let source = directory.appending(path: "broken-skill")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                atPath: source.appending(path: "SKILL.md").path,
                withDestinationPath: "../nowhere/SKILL.md"
            )

            let store = SkillStore(
                skillsDirectoryURL: directory.appending(path: "skills"),
                agent: .claudeCode
            )
            #expect(throws: SkillStoreError.self) {
                try store.importSkill(from: source)
            }
        }

        @Test func importReportsALinkTargetItCannotRead() throws {
            let directory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }

            // Stand in for a sandbox denial by making the target unreadable.
            let vault = directory.appending(path: "vault")
            try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
            let target = vault.appending(path: "SKILL.md")
            try "---\nname: locked\n---".write(to: target, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: target.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path) }

            let source = directory.appending(path: "locked-skill")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                atPath: source.appending(path: "SKILL.md").path,
                withDestinationPath: "../vault/SKILL.md"
            )

            let skillsDirectory = directory.appending(path: "skills")
            let store = SkillStore(skillsDirectoryURL: skillsDirectory, agent: .claudeCode)

            var thrown: SkillStoreError?
            #expect(throws: SkillStoreError.self) {
                do {
                    try store.importSkill(from: source)
                } catch let error as SkillStoreError {
                    thrown = error
                    throw error
                }
            }
            guard case .unreadableLinkTarget(let name, let targetDirectory) = thrown else {
                Issue.record("expected unreadableLinkTarget, got \(String(describing: thrown))")
                return
            }
            #expect(name == "SKILL.md")
            #expect(targetDirectory.hasSuffix("/vault"))

            // A failed import must not leave a half-copied folder behind.
            #expect(try store.list().isEmpty)
            #expect(!FileManager.default.fileExists(atPath: skillsDirectory.appending(path: "locked-skill").path))
        }
}

@Suite("Replacing")
struct Replacing {
        @Test func replacesAFolderOfTheSameName() throws {
            let directory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }

            let source = directory.appending(path: "source/shared-skill")
            try writeSkillFolder(at: source, body: "New body")

            let skillsDirectory = directory.appending(path: "skills")
            let store = SkillStore(skillsDirectoryURL: skillsDirectory, agent: .codex)
            // An older copy, with a stray file that must not survive.
            let existing = skillsDirectory.appending(path: "shared-skill")
            try writeSkillFolder(at: existing, body: "Old body")
            try "stale".write(to: existing.appending(path: "NOTES.md"), atomically: true, encoding: .utf8)

            let replaced = try store.replaceSkill(from: source)

            #expect(try String(contentsOf: replaced.skillFileURL, encoding: .utf8).contains("New body"))
            #expect(!FileManager.default.fileExists(atPath: existing.appending(path: "NOTES.md").path))
            #expect(try store.list().count == 1)
        }

        @Test func copiesWhenTheTargetHasNothingByThatName() throws {
            let directory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }

            let source = directory.appending(path: "source/fresh-skill")
            try writeSkillFolder(at: source, body: "Body")

            let store = SkillStore(
                skillsDirectoryURL: directory.appending(path: "skills"),
                agent: .gemini
            )
            try store.replaceSkill(from: source)

            #expect(try store.list().map(\.directoryName) == ["fresh-skill"])
        }
}

@Suite("Saving and deleting")
struct SavingAndDeleting {
        @Test func saveOverwritesAndDeleteRemoves() throws {
            let directory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = makeSkillStore(in: directory)

            let skill = try store.create(named: "editable", content: "v1")
            try store.save(content: "v2 content", to: skill)
            #expect(try store.readContent(of: skill) == "v2 content")

            try store.delete(skill)
            #expect(try store.list().isEmpty)
        }
}
}
