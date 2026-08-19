import Foundation
@testable import XCAgentHub

/// Creates an isolated temporary directory for one test.
func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "XCAgentHubTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A store rooted at `skills/` inside `directory`.
func makeSkillStore(in directory: URL) -> SkillStore {
    SkillStore(skillsDirectoryURL: directory.appending(path: "skills"), agent: .claudeCode)
}

/// Writes a skill folder whose SKILL.md holds `content` verbatim.
func writeSkill(named name: String, content: String, in skillsDirectory: URL) throws {
    let dir = skillsDirectory.appending(path: name)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try content.write(to: dir.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
}

/// Writes a skill folder with frontmatter naming it after its own directory.
func writeSkillFolder(at url: URL, body: String) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try "---\nname: \(url.lastPathComponent)\n---\n\(body)"
        .write(to: url.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
}
