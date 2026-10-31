# Pitwall

A native macOS front end for [Claude Code](https://docs.claude.com/en/docs/claude-code/overview). It drives your own `claude` CLI, so your login, settings, skills, plugins, MCP servers and session history all carry over, and you work with many sessions at once on a dark, terminal-flavoured board.

> **Status: early (0.1).** Usable day to day, but expect rough edges. See [Known limitations](#known-limitations).
>
> Pitwall is an independent, community project. It is **not affiliated with or endorsed by Anthropic**. "Claude" and "Claude Code" are trademarks of Anthropic.

## Features

- **Pit Wall**: a board of your sessions as *Working*, *Needs you* and *Done today*, with live step feeds, to-do progress, cost, and one-click approvals right on the card.
- **Tabs**: open as many sessions as you like side by side in tabs. Closing a tab never stops a session.
- **Open only what you choose**: Pitwall shows and loads just the project folders you open (several at once). Closing a project hides it; your history is never deleted.
- **Your real history**: reads Claude Code's own transcripts in `~/.claude`, so terminal sessions appear here and Pitwall sessions appear in your terminal. A session running in a terminal updates live.
- **Full command support**: `/` menu with every command, skill, plugin command and MCP prompt you have; `@` file mentions; `!` shell; image paste and drop. Commands the CLI only runs in its terminal UI (`/resume`, `/permissions`, `/memory`, `/mcp`, `/diff`, `/export` and more) are implemented natively.
- **Native approvals**: tool permissions, Claude's questions and plan approval appear as cards, with "always allow" support.
- **Inspector**: live *Changes* diff (with revert), *Plan*/to-dos, *Context* usage, *Files* touched.
- **Everything switchable live**: model, effort and permission mode.
- **Hand-off to Terminal** with one shortcut, and fork any session.
- **Settings (⌘,)**: choose the `claude` location, the default permission mode, and more. Quit asks first if sessions are still working, and folders dropped on the Dock icon open as projects.

## Requirements

- macOS 26 (Tahoe) or later, Apple silicon or Intel.
- [Claude Code](https://docs.claude.com/en/docs/claude-code/setup) installed and signed in (`claude` on your `PATH`, `~/.local/bin`, or Homebrew).

## Install

Download the notarized `.dmg` from [Releases](../../releases), drag **Pitwall** to Applications, and open it. Verify the download against the `.sha256` published with each release.

#### Unsigned builds

Releases made without an Apple Developer ID are marked **pre-release** and are *ad-hoc signed, not notarized*. macOS will refuse to open them at first ("Apple could not verify…"). To approve one: open **System Settings → Privacy & Security**, scroll to the Pitwall message and click **Open Anyway**, or run `xattr -dr com.apple.quarantine /Applications/Pitwall.app`. Only do this for a build you trust; compare its SHA-256 with the `.sha256` file on the release. A build you compile yourself on your own Mac never shows this warning.

### Build from source

You need Xcode 26 (or the matching Command Line Tools).

```sh
git clone <this repository> && cd pitwall
Scripts/build.sh run          # builds build/Pitwall.app (ad-hoc signed) and opens it
swift test                    # unit tests (needs a working Xcode toolchain)
```

`Scripts/build.sh` calls `swiftc` directly and also works on a bare Command Line Tools install where `swift build` is broken. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Keyboard shortcuts

| | |
|---|---|
| ⌘N / ⌘T | New session (tab) |
| ⌘W / ⇧⌘W | Close tab / close window |
| ⌃Tab, ⌃⇧Tab, ⇧⌘] , ⇧⌘[ | Next / previous tab |
| ⌘1 / ⌘2 | Pit Wall / Sessions |
| ⌘K | Search every session and prompt |
| ⌘O | Open one or more project folders |
| ⌘, | Settings |
| ⇧⌘T | Continue this session in Terminal |
| ⌘. , Esc | Stop the current response |
| ↑ in an empty prompt | Recall earlier prompts for this project |

## Privacy and security

Pitwall has **no telemetry, no analytics, no accounts and makes no network connections of its own**. It reads and writes only local files (`~/.claude`, the folders you open) and talks to the `claude` process it launches; that CLI talks to Anthropic under its own terms. Transcripts can contain secrets, so Pitwall keeps them on your Mac and never uploads them. Details: [PRIVACY.md](PRIVACY.md). To report a vulnerability: [SECURITY.md](SECURITY.md).

Pitwall is intentionally **not sandboxed** (a sandbox would prevent launching your CLI and reading `~/.claude`). It is signed with the Hardened Runtime and notarized. **Full access** mode disables all of Claude Code's permission checks and asks for confirmation before enabling.

## Troubleshooting

- **"Claude Code wasn't found" banner.** Install Claude Code, or choose its location in Settings (⌘,). Pitwall looks in `~/.local/bin`, Homebrew and your login shell's `PATH`.
- **"Not logged in" in a session.** Click *Log in in Terminal* on the message, or run `claude auth login`.
- **macOS asks about Desktop / Documents / Downloads access.** That is Claude Code, started by Pitwall, reaching a folder you opened. Allow it for the folders you want to work in.
- **A session shows "Live in a terminal".** It is also running in a terminal, so Pitwall follows it read-only; use *Fork & Continue Here* to work on a copy.
- **Reporting a bug.** Use **Help → Copy Diagnostics** and paste it into the issue. It contains versions and counts only, never paths or content.

## Known limitations

- No embedded terminal; Pitwall hands off to Terminal.app instead.
- `/rewind` checkpoints, background-task panel and a light theme are not implemented yet.
- Subagent activity appears only as the parent's tool card.
- Relies on observed, only partly documented behaviour of Claude Code's headless protocol ([docs/CLAUDE_CODE_PROTOCOL.md](docs/CLAUDE_CODE_PROTOCOL.md)); a CLI update can break things. Please report it.
- English only for now.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Claude Code protocol notes](docs/CLAUDE_CODE_PROTOCOL.md)
- [Releasing](docs/RELEASING.md)
- [Changelog](CHANGELOG.md)

## Contributing

Issues and pull requests are welcome; start with [CONTRIBUTING.md](CONTRIBUTING.md) and the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

[MIT](LICENSE).
