# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
