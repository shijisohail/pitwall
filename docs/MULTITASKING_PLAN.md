# Multitasking like the Claude Code terminal: findings and plan

**Status:** steps 1 to 4 below are built, along with a built-in file viewer (see the changelog). What remains open is the unverified question about `side_question` context, below.

Goal: while Claude works, you can ask a side question, watch and control background commands, and run shell commands, as in the terminal. Protocol details and evidence: [CLAUDE_CODE_PROTOCOL.md](CLAUDE_CODE_PROTOCOL.md#multitasking-side-questions-background-tasks-monitor--shell).

## What the CLI does, and where Pitwall is

| Feature in the terminal | CLI mechanism (verified, 2.1.316) | Pitwall today |
|---|---|---|
| `/btw` side question, answered mid-turn | control request `side_question` | Listed as terminal-only; typed while working, it is queued as ordinary text |
| Background shell commands, a task list | `task_started/updated/notification`, `background_tasks_changed` | Parsed for the optional Agent view only; `local_bash` tasks are ignored |
| Ctrl+B: move a running command to the background | control request `background_tasks` | Missing |
| Peek at a task's output / kill it | `get_task_output`, `stop_task` | Missing |
| Monitor: a stream of events that wake Claude | background task; each stdout line starts an autonomous turn | Unhandled UI-wise; the extra turns just appear |
| `!` shell command | local, recorded as `<bash-input>`/`<bash-stdout>`, no model turn | `runLocal`: runs to completion, output only at the end, no stop, no background, no persistent folder |

## Plan, in order of value

1. **`/btw` (small).** Intercept `/btw <question>` in the composer, never queue it. Send `side_question` with the conversation's earlier side Q&As as `history`. Show the answer in a dismissible card above the composer, not in the transcript. Works idle or running.
2. **Tasks (medium).** Track `local_bash` tasks from the events. A "Tasks" pill in the running bar lists them (description, status, elapsed). Per task: view live output (poll `get_task_output` about once a second while open), Stop (`stop_task`). On a running Bash tool card: "Run in background" (⌘B → `background_tasks`).
3. **Autonomous turns (small).** Make sure a turn that starts without a user message (Monitor) shows as such ("Monitor event") and does not break the running indicator or the queue.
4. **`!` shell as a live task (medium).** Stream output as it arrives, add Stop and Background, keep the working folder between commands (`cd` sticks), still defer the result to the next message as context.

## Risks and open questions

- Whether `side_question` can use the main conversation's context is unverified; test before promising it in the UI.
- These are observed behaviours of a fast-moving CLI. Feature-detect: if a request returns an error or an unknown subtype, hide the control and fall back to today's behaviour.
- `!` commands are Pitwall's own processes, not CLI tasks, so they cannot use `get_task_output` and need their own output buffer.
- Polling cost: poll only while the output view is open.

## Testing

Extend the fake `claude` in `RunnerIntegrationTests` to answer `side_question`, `get_task_output`, `stop_task`, `background_tasks`, and to emit task events and autonomous turns. A live probe (scripted client, `--model haiku --no-session-persistence`) is how the facts above were established.
