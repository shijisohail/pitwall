# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0]

First public version.

### Added
- Pit Wall board (*Working*, *Needs you*, *Done today*) with live step feeds, to-do progress and inline approvals.
- Browser-style tabs for multiple sessions at once; drag to reorder, keyboard navigation.
- Workspace: open only the project folders you choose (several at once), with a picker fed by your Claude Code history.
- Reads Claude Code's own history (`~/.claude`), live-tails sessions running in a terminal, forks sessions, hands off to Terminal.
- Slash-command menu for every command, skill and plugin command, plus native implementations of terminal-only commands.
- Native cards for tool permissions, Claude's questions and plan approval.
- Inspector with live Changes diff (and revert), Plan, Context and Files tabs.
- Live model, effort and permission-mode switching; image attachments; `@` file mentions; `!` shell commands.
- Dark, terminal-inspired theme.
- Universal (arm64 + x86_64) hardened-runtime build, DMG packaging, notarization script, CI and release workflows.
