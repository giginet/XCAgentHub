# Privacy Policy

**AgentHub for Xcode** · Last updated 27 August 2026

AgentHub collects nothing. There is no account, no analytics, no telemetry, and no
crash reporting. Nothing you do in the app is sent to the developer.

## What the app reads and writes

AgentHub edits files that already exist on your Mac, in the folder you grant it access
to on first launch:

- The configuration file of each coding agent, under
  `~/Library/Developer/Xcode/CodingAssistant` — `ClaudeAgentConfig/.claude.json`,
  `codex/config.toml`, and `gemini/settings.json`.
- The skill folders next to them, each holding a `SKILL.md`.

Before overwriting any of these, the app copies the file into its own Application Support
folder (`~/Library/Containers/me.giginet.XCAgentHub/Data/Library/Application Support/XCAgentHub/Backups`)
and keeps the ten most recent copies per agent. Those backups stay on your Mac.

The app is sandboxed. It cannot read anything outside the folder you granted, and the
grant is stored as a security-scoped bookmark in the app's own preferences.

## Network use

AgentHub makes exactly one kind of network request, and only when you ask for it: when
you press **Test Connection** on an HTTP MCP server, the app sends an MCP `initialize`
request to the URL you entered in that server's settings, and shows you the name the
server answers with.

That request goes to the server you named and nowhere else. The app contacts no other
host — no update check, no usage reporting, no third-party service.

## Third-party code

The app bundles two open source libraries,
[swift-toml](https://github.com/mattt/swift-toml) and
[Milepost](https://github.com/giginet/Milepost). Neither performs any networking or data
collection at runtime. Their licenses are shown in the app under
**AgentHub → Open Source Licenses**.

## Children

AgentHub is a developer utility. It is not directed at children and collects no
personal information from anyone.

## Changes

If this policy ever changes, the revised version will be published at this address and
the date above will be updated.

## Contact

Questions about this policy: open an issue at
<https://github.com/giginet/XCAgentHub/issues>.
