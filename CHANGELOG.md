# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.1.1] - Unreleased

### Fixed
- Crash in the composer when attached images were cleared (sending, queueing or removing a thumbnail) while the thumbnail strip was updating.

## [1.1.0] - 2026-10-31

### Changed
- The idle Pit Wall board is now an interactive home: a time-of-day greeting with a quick-start prompt, one-click task tiles, project cards (continue the latest session, start a new one, see what's working or waiting) and recent sessions. The first-launch screen has a folder drop zone and recent-project cards.

### Fixed
- Background-agent `<task-notification>` messages no longer show as a raw XML bubble. They render as a one-line status (agent name, duration, tools, tokens) with a Log button and click-to-expand raw text.

### Security
- Approving a tool from the Pit Wall board now shows the full command, diff or arguments (scrollable), the same as the chat card, instead of a clipped one-line summary.
- Clicking a file path from a session no longer launches apps, scripts or other executables: those are revealed in Finder instead of opened.
- Terminal handoff scripts are created owner-only (0700) and removed a minute after launch.

### Added
- Message queue: keep typing while Claude is working. Messages queue above the input and go out one at a time as each turn finishes. Each queued message can be sent now (interrupts the current turn), edited or removed; ↑ on an empty input edits the newest one, and Esc/Stop hands the whole queue back to the input.
- ⇧Tab cycles the permission mode (ask → accept edits → plan), as in Claude Code. Full access is never reachable by shortcut.
- Drag and drop into the chat: drop screenshots, image files or images dragged from a browser anywhere on the chat pane (with a "Drop to attach" highlight). Other files and folders are added to the prompt as `@path` mentions.

## [1.0.0] - 2026-10-31

First release.

### Added
- Pit Wall board (*Working*, *Needs you*, *Done today*) with live step feeds, to-do progress and inline approvals.
- Browser-style tabs for multiple sessions at once; drag to reorder, keyboard navigation.
- Workspace: open only the project folders you choose (several at once), with a picker fed by your Claude Code history.
- Reads Claude Code's own history (`~/.claude`), live-tails sessions running in a terminal, forks sessions, hands off to Terminal.
- Slash-command menu for every command, skill and plugin command, plus native implementations of terminal-only commands.
- Native cards for tool permissions, Claude's questions and plan approval.
- Inspector with live Changes diff (and revert), Plan, Context and Files tabs.
- Live model, effort and permission-mode switching; image attachments; `@` file mentions; `!` shell commands.
- Dark, terminal-inspired theme (background animation is opt-in; idle CPU is 0%).
- Settings window (⌘,): `claude` location, default permission mode, animation, history options.
- First-run health check with a banner when the `claude` CLI is missing.
- Quit confirmation while sessions are working; folders dropped on the Dock icon open as projects.
- Help → Copy Diagnostics (versions and counts only).
- Security: only http, https and mailto links in model output can open; tool output stored in memory is capped; stale hand-off scripts are cleaned up; session ids are shell-quoted.
- Transcripts, live tailing and command catalogs load only for the session being shown, never while the board is showing.
- Accessibility: Reduce Motion respected, VoiceOver labels for sessions, tabs and status.
- Unsigned release path (`UNSIGNED=1`) for building a DMG without an Apple Developer account.
- Universal (arm64 + x86_64) hardened-runtime build, DMG packaging, notarization script, CI and release workflows.
