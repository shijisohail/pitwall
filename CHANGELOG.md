# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Settings → Browser → Claude in Chrome.** Starts sessions with `--chrome` so Claude can drive your Chrome (needs the Claude in Chrome extension, signed in to the same account). Off by default, and applies to sessions started or restarted after you turn it on.

## [1.4.0] - 2026-11-12

### Added
- A **glass look**. The window blurs the desktop behind it, and cards, buttons, the tab bar and the area behind the prompt box are dark Liquid Glass. The lime-on-near-black theme is unchanged. **Settings → Appearance → Glassiness** sets how see-through it is, from solid to clear. macOS Reduce Transparency keeps the window solid.
- **Full screen around the notch.** On a Mac with a camera notch, **Settings → Full screen → Use the area around the notch** makes full screen use the row beside the notch: tabs fill the space on the left of it and carry on to the right, and Close / Minimize / Exit Full Screen buttons appear at the top left. It replaces macOS's own full screen while on (⌃⌘F or the green button toggles it), so it is off by default.
- A short sound when a session finishes its turn, so you can look away while Claude works. On by default; turn it off in Settings → "Play a sound when a session finishes". It stays quiet when you stop a run yourself.

### Fixed
- A long `/btw` answer, a card with many questions, or several approvals could grow until they pushed the prompt box off the window, with no way to scroll. They now cap their height and scroll, and Skip / Submit stay in view.
- The tab's **✕** only responded over the thin strokes of the glyph, so a click a few pixels off did nothing. It now has a proper click target.
- The tab strip now scrolls the selected tab fully into view, including when the window opens. A new or far-right tab could be left as a sliver beside the **+** button, where it could not be clicked.

## [1.3.2] - 2026-11-05

### Added
- A pink **N agents working** badge in the running bar above the prompt whenever Claude has subagents going. It no longer needs the Agent view turned on. A tab also shows an agent count when two or more are running in that session.

### Fixed
- Reordering tabs: dragging a tab to the right did nothing and the last slot could not be reached. A dropped tab now takes the slot of the tab it lands on, in either direction.
- The tab strip scrolls to the selected tab, so a new or far-right tab is no longer clipped behind the **+** button.

## [1.3.1] - 2026-11-04

### Added
- **Pin to Top** (right-click a session): pinned chats get a **Pinned** section above the projects, in pin order, and are not repeated under their project. Pins survive a relaunch.
- New sessions get a generated name, as in the terminal. The first prompt stands in until the first reply finishes, then Pitwall asks the CLI for a title (a bare `/rename`) and it is saved in the session's transcript.

### Fixed
- A "Claude has a question" card with many questions no longer pushes Submit and Skip off-screen: the questions scroll inside the card, with the buttons pinned below.
- A narrow table in a reply now hugs its columns. Before, its border and background stretched across the whole chat width and left an empty bordered area to the right.

## [1.3.0] - 2026-11-02

### Added
- `/btw` side questions: answered on the side while Claude is busy, in a card above the prompt, never part of the conversation and never queued. Also works when nothing is running.
- A **Tasks** bar for the shell commands Claude runs: background commands, Monitors, and a command Claude is waiting on. Each shows its status and time, live output, Stop, and, for a foreground command, "Run in background" (<kbd>⌘B</kbd>, as Ctrl+B in the terminal). `/tasks` opens it.
- When Claude starts a turn nobody asked for (a Monitor line, a finished background task) it now shows as running with a "Background activity" note, and messages you type meanwhile queue instead of colliding with it.
- `!` shell commands stream their output live, can be stopped (the whole process tree), no longer wait for the command to finish before showing anything, and `cd` carries over to the next command.
- A **Copy** button under every finished reply. It copies the reply as clean text (no Markdown symbols, blank lines between paragraphs); its arrow offers the Markdown source, and right-click offers both. Code blocks keep their own Copy button.
- A built-in file viewer. File names in replies, the Files and Changes tabs, memory files and logs open in Pitwall: Markdown rendered (with a Source toggle and Back for linked files), code and text with line numbers, JSON pretty-printed, images, PDFs, and Office files, audio and video via Quick Look. Open, Reveal and Copy Path are in its header; <kbd>⇧⌘O</kbd> views any file. It is read-only; apps, installers and executables are only revealed in Finder, never opened.

### Fixed
- Text in a reply can be selected across paragraphs, bullets and lines (drag, double-click a word, ⌘A, ⌘C). Before, a selection stopped at the edge of each paragraph. A run of paragraphs, headings, bullets and quotes is now one native text view; links in replies stay clickable, and code blocks and tables keep their own views.

## [1.2.2] - 2026-11-02

### Added
- Type anywhere in a chat, as in a terminal. After clicking the transcript, selecting text or tapping a button you no longer need to click the prompt box: just type, and the keystrokes go into it, after any draft already there. Shortcuts (⌘ or ⌃), Space, arrows, Return, Tab and Escape are left alone (so buttons and scrolling keep working), and other windows (Settings, sheets, alerts) are never affected.
- Prompt keywords are highlighted. In the input as you type, and in the message once sent: `ultrathink`, `ultracode` and `ultraplan` anywhere in the prompt (matched the way Claude Code matches `ultrathink`: a whole word, any case), a `/command` at the start (only when it names a real command, so a half-typed one stays plain), `@file` mentions, and a leading `!` for a shell command. Sent messages show them in colour (these keywords in a per-letter rainbow); the input tints a highlight behind the text, so the text and cursor are untouched.

### Fixed
- Returning to the window, or closing a sheet, no longer leaves your draft fully selected (where the next keystroke would have replaced all of it); the cursor goes to the end instead.

### Documentation
- Explained the macOS notice "“Pitwall” was prevented from modifying apps on your Mac" (README Troubleshooting, PRIVACY): it is App Management blocking a command Claude ran, which macOS attributes to Pitwall, and nothing was changed.

## [1.2.1] - 2026-11-01

### Added
- A running indicator above the composer while a session is working: a pulsing dot, what Claude is doing right now ("Reading Composer.swift", "Run the tests", "Waiting for your approval"), a live timer, queued-message and agent counts, and a sweeping line. Amber while it waits for you.
- File names in replies are clickable. A code span such as `reports/summary.pdf`, `src/App.swift:42` or `~/notes.md` that names a file or folder that exists (relative to the session's folder, or absolute) opens it; an app or script is revealed in Finder instead of launched. A bare file name that follows a mentioned folder ("Files are in `reports/`:" then the names) resolves inside that folder. Names that don't exist, and ordinary code, stay plain.

### Fixed
- The cursor is ready to type more often: the composer takes focus back when you return to the app, after a sheet closes, after you Allow or Deny a request, and once a reopened session finishes loading.
- A long prompt in the composer is now scrollable: the box grows with your text up to about ten lines, then scrolls, so you can read and edit the top of a long or pasted prompt. Queued messages show their full text on hover.
- Links in replies can be clicked again. They were styled as links but did nothing, because SwiftUI's selectable text swallows clicks. Text that contains a link is now left non-selectable so it opens (right-click it for Copy Text); everything else, including code blocks and tables, stays selectable.

## [1.2.0] - 2026-11-01

### Added
- Agent view (optional, off by default): when Claude spawns subagents, an Agents tab in the inspector shows each one as a little bot on a canvas. It moves to Think, Read, Search & web, Edit or Run as it works, shows what it is doing in a speech bubble, springs out of the agent that spawned it, and rests along the bottom when done. A roster below lists each agent with its state, time, tools and tokens, and expands to its task, steps and report. Reopened sessions show finished agents too. Turn it on in Settings, Agents, or from a session's … menu; turning it off hides the tab and stops tracking.

### Changed
- Fewer surprises from macOS folder-permission pop-ups: Settings gains a Permissions section (Full Disk Access status and shortcuts to the right System Settings panes), and a one-time dismissible tip on the home and welcome screens explains why macOS asks and offers a single optional alternative.
- `Scripts/setup-local-signing.sh` creates a stable local signing identity, and `Scripts/build.sh` uses it automatically, so rebuilding on your own Mac no longer makes macOS forget your folder permissions. Docs explain why signed releases keep permissions across updates and ad-hoc ones don't.
- Release builds are never signed with the local development identity: `release.sh`'s unsigned path now names ad-hoc signing explicitly.

### Fixed
- Markdown tables render as real tables (header row, column alignment, wrapping cells, zebra rows, bold and code inside cells) instead of raw `| pipes |` in a code block. Wide tables shrink to fit the chat instead of overflowing.

## [1.1.1] - 2026-10-31

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
