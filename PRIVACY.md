# Privacy

Pitwall is a local application. This page says exactly what it touches.

## What Pitwall collects

Nothing. There is no telemetry, analytics, crash reporting, account system or update ping. Pitwall makes **no network connections of its own**.

## What Pitwall reads and writes

| Where | Why | Access |
|---|---|---|
| `~/.claude/projects/**/*.jsonl` | Show your Claude Code session history and live-update sessions running elsewhere | read only |
| `~/.claude/history.jsonl` | Prompt recall (↑) and search | read only |
| `~/.claude/settings*.json`, `CLAUDE.md`, memory files | The Settings, Memory and Permissions viewers | read only (opened in your editor on request) |
| Folders you open | The `claude` process works there; the `git diff`, file list and revert features run `git` there | as directed by you and Claude Code |
| App preferences (`UserDefaults`) | Your opened folders, tabs, Settings choices (including a custom `claude` path). Never prompts or transcript content | read/write |
| A temporary `.command` file | Hand-off to Terminal | write, in the system temp directory |

## The `claude` process

Pitwall launches your installed Claude Code CLI. That CLI sends your prompts and the context it gathers to Anthropic under Claude Code's own terms and your own account. Pitwall does not intercept, copy or forward that traffic.

Commands Claude runs are child processes of Pitwall, so macOS attributes what they do to Pitwall. That is why you may see a macOS notice such as "“Pitwall” was prevented from modifying apps" when a command touches another app. It is macOS blocking that command, not Pitwall changing anything; see [Troubleshooting](README.md#troubleshooting).

## Logging

Pitwall writes to the unified log (`Console.app`) with the subsystem equal to its bundle id. It records events such as "started claude" and "scanned N sessions", never prompts, paths or transcript text.

## Your control

Remove an opened project from Pitwall at any time (it only hides it; nothing on disk is deleted). Delete Pitwall's preferences with `defaults delete <bundle id>`. Your Claude Code history is managed by Claude Code itself.
