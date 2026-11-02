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

## Multitasking: side questions, background tasks, Monitor, `!` shell

Verified live against **Claude Code 2.1.316**, 2026-11-02, by driving a real `claude -p --input-format stream-json` session (a scripted client that sent control requests while a turn was running).

### Side questions (`/btw`)

`/btw` is declared `immediate` with `thinClientDispatch: "control-request"`, i.e. the CLI expects a thin client to send a control request, not text.

- Request: `{"subtype":"side_question","question":"…","history":[{"question":"…","response":"…"}]}`. `history` is the earlier side Q&As, all strings; send `[]` the first time.
- Preceded by `system/control_request_progress`, then `control_response` → `{"response":"<answer>","synthetic":false}`.
- **Works while a turn is running.** Sent mid-turn it was answered 1.8 s later, before the main turn's `result`. It produced no `assistant` or `result` event, so it never touches the main transcript.
- Not verified: whether the answer can use the main conversation's context.

### Background tasks

A shell command that is running (foreground or background) is a *task*. Events (`system`):

| subtype | fields |
|---|---|
| `task_started` | `task_id`, `run_id`, `tool_use_id`, `description`, `is_backgrounded`, `task_type` (`local_bash` or `local_agent`) |
| `task_updated` | `task_id`, `run_id`, `patch`: `{is_backgrounded:true}` or `{status:"killed"\|"completed", end_time}` |
| `task_notification` | `task_id`, `run_id`, `tool_use_id`, `status` (`stopped`, `completed`), `output_file`, `summary` |
| `background_tasks_changed` | `tasks`: the live list (`task_id`, `run_id`, `task_type`, `description`), empty when none |

Control requests, all working in `-p` mode:

| subtype | args | response |
|---|---|---|
| `background_tasks` | `tool_use_id` of the running Bash call | `{"backgrounded":true}`. This is Ctrl+B. The model's tool result becomes "Command was manually backgrounded by user with ID …. Output is being written to: <file>" and the turn carries on. |
| `get_task_output` | `task_id` | `{"output","total_bytes","truncated"}`, live partial output |
| `stop_task` | `task_id` | `{}`, then `task_updated {status:"killed"}`, `task_notification {status:"stopped"}`, empty `background_tasks_changed` |

Output also lands in `<claude tmp>/<session id>/tasks/<task_id>.output`. The CLI refuses a bare long `sleep` in the foreground and the model re-runs it with `run_in_background`.

### Monitor

`Monitor` is a deferred tool (the model fetches it with `ToolSearch`). It starts a background `local_bash` task (`is_backgrounded:true`) that expires after about a minute unless its source ends first. **Every stdout line becomes a notification that starts an autonomous model turn**: `assistant` and `result` events arrive with no user message. The task ends with `task_updated {status:"completed"}` and a `task_notification`.

### `!` shell in the terminal UI

Not available headlessly. The terminal records it as two user messages, `<bash-input> cmd</bash-input>` then `<bash-stdout>…</bash-stdout><bash-stderr>…</bash-stderr>`, and starts no model turn. Pitwall's own `runLocal` stands in for it.

## On-disk history

`~/.claude/projects/<cwd with "/" and "." replaced by "-">/<sessionId>.jsonl`, one record per content block (merge blocks sharing `message.id`). Title records: `custom-title` (set by `/rename`) beats `ai-title`. The first user record carries `cwd`, `gitBranch` and `entrypoint` (`cli`, `sdk-cli`, `claude-desktop`). `~/.claude/history.jsonl` lists every typed prompt with project and session.

## Subagents (observed with Claude Code, `-p` stream-json, `--include-partial-messages`)

Spawning an agent is an `Agent` (older: `Task`) tool call with input `description`, `prompt`, `subagent_type`, `run_in_background`. In `-p` mode the calls came back as **async** ("Async agent launched successfully…") even without `run_in_background`, so the tool result is not the agent's report.

Lifecycle events (all `type: "system"`, `task_id` is the agent's id, `tool_use_id` is the spawning `Agent` tool_use id):

| subtype | fields |
|---|---|
| `task_started` | `description`, `subagent_type`, `is_backgrounded`, `spawn_depth` (1 = spawned by the main thread), `task_type` (`local_agent`), `prompt` |
| `task_progress` | `description` (what it is doing now, e.g. "Running Count entries…"), `usage` `{total_tokens, tool_uses, duration_ms}`, `last_tool_name` |
| `task_updated` | `patch` `{status, end_time(ms)}` |
| `task_notification` | `status` (`completed`, …), `summary` (the agent's final text), `usage`, `output_file` |
| `background_tasks_changed` | `tasks`: the currently running background tasks |

An agent's own steps arrive as ordinary `assistant` (thinking / text / tool_use) and `user` (tool_result) events carrying `parent_tool_use_id` (the spawning tool_use id) plus `agent_id`, `subagent_type`, `task_description`. **No `stream_event` deltas are sent for subagents**, only complete events. A nested agent is an `Agent` tool_use inside events whose `parent_tool_use_id` is the outer agent. After background agents finish, the CLI starts further turns on its own, so one prompt can produce several `result` events.

Fixture: `Tests/PitwallTests/AgentsFixture.swift`.
