<p align="center">
  <img src="screenshots/icon.png" width="128" alt="AgentHub app icon">
</p>

# AgentHub for Xcode

[![macOS](https://img.shields.io/badge/macOS-26%2B-white?logo=apple&logoColor=white)](https://developer.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.3-orange?logo=swift&logoColor=white)](https://swift.org/)
[![Xcode](https://img.shields.io/badge/Xcode-26.4%2B-blue?logo=xcode&logoColor=white)](https://developer.apple.com/xcode/)
[![CI](https://github.com/giginet/XCAgentHub/actions/workflows/test.yml/badge.svg)](https://github.com/giginet/XCAgentHub/actions/workflows/test.yml)
[![License](https://img.shields.io/badge/License-Apache%202.0-green)](LICENSE)
[![Mac App Store](https://img.shields.io/itunes/v/6802938470?label=Mac%20App%20Store&logo=apple&logoColor=white&color=0D96F6)](https://apps.apple.com/app/id6802938470)

<p align="center">
  <a href="https://apps.apple.com/app/id6802938470">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-mac-app-store/white/en-us">
      <img src="https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-mac-app-store/black/en-us" alt="Download on the Mac App Store" height="48">
    </picture>
  </a>
</p>

A macOS app for managing the MCP servers and skills of the coding agents that run inside Xcode.

AgentHub is an independent project. It is not made by Apple, and is not affiliated with,
endorsed by, or sponsored by Apple Inc. Xcode is a trademark of Apple Inc.

Xcode keeps each agent's configuration in its own file, in its own format, under
`~/Library/Developer/Xcode/CodingAssistant`. AgentHub puts all three in one window
and writes each file in the format that agent expects.

![MCP server list](screenshots/1-list-mcp.png)

## What it manages

| Agent | MCP servers | Skills |
| --- | --- | --- |
| Claude Code | `ClaudeAgentConfig/.claude.json` | `ClaudeAgentConfig/skills` |
| Codex | `codex/config.toml` | `codex/skills` |
| Antigravity | `gemini/settings.json` | `gemini/skills` |

Pick an agent in the sidebar; the segmented control switches between its MCP servers
and its skills.

## MCP servers

Add stdio and HTTP servers, edit them, and toggle one off without deleting it — the
server is stashed in whichever disabled list that agent understands, so turning it
back on restores it as it was. HTTP servers can be checked with **Test Connection**,
which performs an MCP `initialize` handshake and reports the server name it answers
with.

Every write backs up the configuration file first, and unrelated keys in the file are
preserved.

The copy button in the bottom bar sends the selected servers to another agent, written
in that agent's own format. If the target already has a server of the same name, it
asks before replacing it.

![Editing an MCP server](screenshots/2-edit-mcp.png)

## Skills

A skill is a folder holding a `SKILL.md` with YAML frontmatter. AgentHub lists what
each agent has, and creates or edits one through a form rather than a text editor:
dedicated fields for `name`, `description`, and `allowed-tools`, a key/value table for
anything else, and the Markdown body underneath.

![Skill list](screenshots/3-list-skills.png)

Existing files are parsed back into the same form. A `SKILL.md` carrying YAML the form
cannot represent — a comment, a block scalar, a nested map — opens as raw Markdown
instead, so nothing is silently rewritten.

![Editing a skill](screenshots/4-edit-skill.png)

**Add from Folder…** copies a skill folder in, following symlinks so the imported copy
is made of real files. The copy button in the bottom bar sends the selected skills to
another agent, asking first if a folder of the same name is already there.

## Privacy

AgentHub collects nothing — no account, no analytics, no telemetry. See
[PRIVACY.md](PRIVACY.md).

## License

AgentHub is released under the Apache License 2.0. See [LICENSE](LICENSE).
