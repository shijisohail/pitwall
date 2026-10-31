# Testing

## Automated (`swift test`)

Swift Testing suites in `Tests/PitwallTests`; CI runs them on every push and pull request.

| Suite | What it proves |
|---|---|
| `TranscriptParserTests` | Claude Code transcripts parse identically in one pass or in arbitrary chunks; tool results attach; injected text is skipped; titles, images, compaction notices |
| `HistoryTests` | Session indexing, title precedence (`/rename` > AI title > first prompt), huge first records, mtime caching, missing files |
| `StoreTests` | Workspace scoping (deepest folder wins), script-session filtering, tabs (open, close, reorder, cycle), lazy loading, persistence |
| `CommandTests` | Slash-command routing: forwarded vs native, aliases, sheets, `/add-dir`, send's return value |
| `EventHandlingTests` | Stream-json events become messages, tool calls, approvals, stop notices, usage meters, output cards; sub-agent events ignored; huge output clipped |
| `RunnerIntegrationTests` | The real `ClaudeRunner` and `Conversation` against a **fake `claude`** that speaks the wire protocol: control requests, streaming, approve and deny, interrupt, missing CLI |
| `DerivedTests` | Changed files, live feed, to-do progress, plan |
| `HardeningTests` | Link policy, output clipping, hand-off cleanup, safe settings defaults, CLI path validation, diagnostics leak nothing |
| `ModelTests` | Permission-mode spellings, catalog parsing, shell quoting, tool summaries |

The tests never call the real `claude` or the network. To drive the app against a different CLI, set `PITWALL_CLAUDE_PATH`.

## Manual checklist (before a release)

Run on a clean macOS user if you can.

- [ ] First launch with no opened projects shows the picker; choosing a folder opens it
- [ ] With `claude` unavailable, the banner appears; *Choose…* and *Retry* recover
- [ ] Send a prompt; the reply streams; cost and context appear
- [ ] A tool needing approval shows a card; Allow, Always and Deny behave; a question card and a plan card work
- [ ] Stop ends a running turn within a second or two and the session still works afterwards
- [ ] Two sessions in two tabs run at once; closing a tab keeps its session running (see Pit Wall)
- [ ] Open an old terminal session: history loads, ↑ recalls prompts, *Open in Terminal* resumes it
- [ ] Run a session in a terminal while it is open here: it updates live and the banner appears
- [ ] Inspector: Changes shows a diff, Revert asks first; Plan, Context, Files populate
- [ ] ⌘, Settings: change the `claude` path and default mode; both take effect
- [ ] Quit while a session is working asks for confirmation
- [ ] Drop a folder on the Dock icon: it opens as a project
- [ ] VoiceOver reads session, tab and status labels; with Reduce Motion on, nothing animates
- [ ] Help → Copy Diagnostics contains no paths or titles

## Performance budget (measured 2026-10-31, Apple silicon)

- Idle with the board open: **0% CPU** (a brief blip every 6 s for the history rescan), **~126 MB** memory footprint (`footprint <pid>`).
- No `claude` child processes while idle.
- The optional animated background costs ~4% CPU while the window is open, which is why it is off by default.
