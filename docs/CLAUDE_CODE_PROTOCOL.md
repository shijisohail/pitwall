# Claude Code headless protocol: observed behaviour

Pitwall depends on how `claude -p --input-format stream-json --output-format stream-json` behaves. Parts of this are documented by Anthropic ([headless mode](https://code.claude.com/docs/en/headless), [Agent SDK: approvals and user input](https://code.claude.com/docs/en/agent-sdk/user-input)); the rest was **observed** and may change between releases.

Verified against **Claude Code 2.1.314**, 2026-10-31. If you verify against a newer version, update this page.

## Launching

```
claude -p --input-format stream-json --output-format stream-json --include-partial-messages --verbose \
       --permission-prompt-tool stdio --permission-mode <mode> [--model m] [--effort e] [--resume id [--fork-session]] [--add-dir d]
```

- `--permission-mode` values: `manual`, `acceptEdits`, `plan`, `auto`, `dontAsk`, `bypassPermissions`. (`default` is rejected; the control protocol still calls manual mode `default`.)
- **Without `--permission-prompt-tool stdio`** the CLI silently denies anything needing approval (a `system/permission_denied` event) and does not offer `AskUserQuestion`.

## Messages

stdin, one JSON object per line:

- User message: `{"type":"user","message":{"role":"user","content":"text" | [ {type:"text"|"image",…} ]}}`. Images: `{"type":"image","source":{"type":"base64","media_type":"image/png","data":"…"}}`.
- Control request: `{"type":"control_request","request_id":"…","request":{"subtype":"…",…}}`.
- Control response (to a `can_use_tool` request): `{"type":"control_response","response":{"subtype":"success","request_id":"…","response":{…}}}`.

stdout events Pitwall uses: `system` (`init`, `session_title_changed`, `compact_boundary`, `api_retry`), `stream_event` (token and tool-input deltas), `assistant`, `user` (tool results), `control_request`, `control_cancel_request`, `rate_limit_event`, `result`.

## Control requests that work

| subtype | args | notes |
|---|---|---|
| `initialize` | none | Returns `commands` (name, description, argumentHint), `models`, `available_output_styles`, `account`. Creates **no** session file. |
| `set_model` | `model` | Live; returns the resolved model id. |
| `set_permission_mode` | `mode` (`default`, `acceptEdits`, `auto`, `dontAsk`, `plan`) | Live. Switching to or from `bypassPermissions` is not done live. |
| `mcp_status` | none | Servers with status, transport, scope, tools. Servers connect asynchronously, so wait a moment after launch. |
| `interrupt` | none | Ends the turn with a `result` of subtype `error_during_execution`; the session stays usable. |

## Approvals (`can_use_tool`)

Request: `{"subtype":"can_use_tool","tool_name","input","description","permission_suggestions":[{"type":"setMode"|"addRules",…}],"tool_use_id","requires_user_interaction"}`.

Reply with `{"behavior":"allow","updatedInput":{…},"updatedPermissions":[<a suggestion>]}` or `{"behavior":"deny","message":"…"}`.

- **`AskUserQuestion`**: `input.questions[]` (`question`, `header`, `options[{label,description}]`, `multiSelect`). Allow with `updatedInput:{questions, answers:{<question text>: <label, or "a, b" for multi>}}`.
- **`ExitPlanMode`**: `input.plan`. Allow to leave plan mode; add a `setMode: acceptEdits` suggestion to also auto-accept edits.

## Slash commands in headless mode

User-invoked skills and custom commands expand normally. These also work and return their text in the `result` event **with no assistant message**: `/context`, `/usage` (`/cost`), `/model`, `/effort`, `/mcp` (summary), `/rename`, `/compact`, `/output-style`, `/config key=value`, `/init`, `/code-review`, `/security-review`, `/goal`, `/fast`, `/clear`.

Terminal-UI-only commands (`/resume`, `/permissions`, `/memory`, `/status`, `/add-dir`, `/hooks`, `/skills`, `/help`, `/rewind`, `/diff`, `/export`, `/branch`, `/login`, …) are not runnable headlessly; Pitwall implements the useful ones natively (`Commands.swift`).

## Other useful facts

- `rate_limit_event.rate_limit_info.unifiedWindows.{five_hour,seven_day}`: `utilization` (0–1) and `resetsAt` (epoch seconds).
- `result.total_cost_usd` is the whole-conversation total, including earlier runs when resumed.
- `result.modelUsage.<model>.contextWindow` gives the context size.
- Slash-command-only turns produce a `result` with text but no `assistant` event.

## On-disk history

`~/.claude/projects/<cwd with "/" and "." replaced by "-">/<sessionId>.jsonl`, one record per content block (merge blocks sharing `message.id`). Title records: `custom-title` (set by `/rename`) beats `ai-title`. The first user record carries `cwd`, `gitBranch` and `entrypoint` (`cli`, `sdk-cli`, `claude-desktop`). `~/.claude/history.jsonl` lists every typed prompt with project and session.
