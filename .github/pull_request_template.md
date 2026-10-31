## What and why

<!-- What does this change, and why? Link the issue it closes. -->

## How I checked it

<!-- Tests added or run; for UI changes, how you exercised it and a screenshot. -->

## Checklist

- [ ] `swift test` and `Scripts/build.sh` pass
- [ ] Tests added or updated for logic changes
- [ ] `CHANGELOG.md` updated under **Unreleased**
- [ ] No prompts, paths or transcript content are logged or stored; no new network access
- [ ] Shell commands built from external values use `TerminalApp.quote`
- [ ] If Claude Code protocol behaviour changed: `docs/CLAUDE_CODE_PROTOCOL.md` updated (with the CLI version)
