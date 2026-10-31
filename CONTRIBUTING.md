# Contributing to Pitwall

Thanks for helping. This guide keeps changes easy to review.

## Ground rules

- Be kind: see the [Code of Conduct](CODE_OF_CONDUCT.md).
- Security issues go through [SECURITY.md](SECURITY.md), not public issues.
- By contributing you agree your work is released under the project's [MIT license](LICENSE).

## Setup

- macOS 26 and Xcode 26 (or the matching Command Line Tools).
- Claude Code installed and signed in, for manual testing.

```sh
Scripts/build.sh run     # universal, hardened-runtime, ad-hoc signed app at build/Pitwall.app
swift build              # debug build via SwiftPM
swift test               # unit tests
```

**Toolchain caveat.** On a Command Line Tools install whose default SDK is newer than its compiler, `swift build` and `swift test` can fail with dyld or "SDK is not supported by the compiler" errors. `Scripts/build.sh` works around this by pinning the macOS 26 SDK. Tests then need a full Xcode (CI has one).

## Project layout

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). In short: `Sources/Pitwall` holds the engine (`ClaudeRunner`, `Conversation`, `Store`, `History`) and `Views/`; `Tests/PitwallTests` holds pure-logic tests.

## Making a change

1. Open an issue first for anything larger than a bug fix, so we can agree on the approach.
2. Keep the diff focused. Match the surrounding code's naming, comment density and idioms; the project builds in Swift 5 language mode and UI/state types are `@MainActor`.
3. Add or update tests for logic changes (parsing, store rules, command routing). UI-only changes: describe how you checked them and attach a screenshot.
4. Never log or persist prompts, file paths or transcript content (`Log` keeps dynamic strings private). Never add network calls or telemetry without an issue and an explicit opt-in design.
5. Anything that builds a shell command must quote untrusted values with `TerminalApp.quote`.
6. Update `CHANGELOG.md` under **Unreleased**.
7. Run `swift test` and `Scripts/build.sh`; both must pass.

### Adding a native slash command

Add its name and description to `nativeCommands`, handle it in `Conversation.routeSlash` (`Sources/Pitwall/Commands.swift`), and add a case to `CommandTests`. Commands the headless CLI already runs need nothing: they are forwarded as text.

### Touching the Claude Code protocol

Behaviour lives in `ClaudeRunner` and `Conversation.handle*`. Record what you verified, and against which CLI version, in [docs/CLAUDE_CODE_PROTOCOL.md](docs/CLAUDE_CODE_PROTOCOL.md).

## Pull requests

Fill in the template, keep commits readable, and expect review comments; they are about the code, not you.
