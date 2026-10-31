# Architecture

Pitwall is a SwiftUI app that drives the user's own `claude` CLI. It owns no model access and no accounts: everything it knows comes from the CLI's JSON stream and from Claude Code's files in `~/.claude`.

```
SwiftUI views ──▶ Store (workspace, tabs, search, usage)
                    │
                    ├── Conversation (one per session; state machine over the event stream)
                    │       └── ClaudeRunner (one `claude -p` child process, JSON lines both ways)
                    └── History / TranscriptParser (reads ~/.claude/projects/**.jsonl)
```

All UI state types are `@MainActor` and `@Observable`. Child-process output is parsed on a background queue and handed to the main actor.

## Modules (`Sources/Pitwall`)

| File | Responsibility |
|---|---|
| `ClaudeRunner.swift` | Spawns `claude -p --input-format stream-json --output-format stream-json …` through a login shell (so the user's `PATH` applies). Writes user messages and control requests; routes `control_response`s to completions; one-shot helpers for the command catalog, session rename. |
| `Conversation.swift` | Turns stream events into messages (text, thinking, tool calls, results); tracks approvals, cost, context, stop/interrupt; live settings (model, permission mode); live-tail of a session file. |
| `Commands.swift` | Slash-command routing (native handlers vs forwarded text), the Terminal hand-off, local `!` shell, export, copy. |
| `Store.swift` | The workspace (opened folders), tabs, search scope, project list, usage windows, sheet routing. Persists to `UserDefaults`. |
| `History.swift` | Indexes sessions cheaply (head and tail of each transcript) and parses full transcripts incrementally (`TranscriptParser`). |
| `Derived.swift` | Per-session derived data from the transcript: changed files, live feed, to-do progress, plan. |
| `Models.swift` | Value types: blocks, messages, permission modes, catalog, approvals. |
| `Views/` | Pit Wall (`Board`), tab bar, session list, chat, composer, inspector, sheets, theme (`HTB`). |

## Key decisions

- **Drive the CLI, don't reimplement it.** Skills, plugins, MCP, hooks and settings keep working because the real CLI runs them. The cost is depending on its (partly documented) headless protocol; see [CLAUDE_CODE_PROTOCOL.md](CLAUDE_CODE_PROTOCOL.md).
- **History is Claude Code's, not ours.** Pitwall has no database of conversations. It indexes `~/.claude` and keeps only preferences. That is why terminal and Pitwall sessions interoperate.
- **Workspace scoping.** `Store.owner(ofPath:)` maps every session to the deepest opened folder; nothing outside the workspace is listed, loaded or tailed. Transcripts load lazily on selection.
- **Not sandboxed.** The sandbox forbids launching the user's CLI and reading `~/.claude`. Hardened Runtime and notarization are used instead.
- **One process per session, kept alive between turns**; model and permission mode change live over control requests; effort, extra folders and Full access restart the process on the next send (resuming the same session).

## Concurrency

`ClaudeRunner` reads stdout on a private queue, splits lines, and `DispatchQueue.main.async`s each parsed event into `Conversation.handle`. Pending control-request completions are only touched on the main thread. File scans (`History.scan`) run in a detached task and publish to the store on the main actor.

## Security-sensitive spots

- Anything building a shell command quotes with `TerminalApp.quote` (`Commands.swift`).
- `Process` arguments are passed as an argv array via `exec "$0" "$@"`, never interpolated into a shell string.
- Transcripts are untrusted input: parsing is defensive (size caps per line, type checks, no force unwraps on external data).
- The revert action runs `git checkout -- <path>` only after a confirmation.

## Testing

`Tests/PitwallTests` (Swift Testing) covers pure logic: transcript parsing, history indexing, store scoping and tabs, command routing, derived data, shell quoting. The CLI itself is not spawned in tests. UI is verified manually; see the checklist in [CONTRIBUTING.md](../CONTRIBUTING.md).
