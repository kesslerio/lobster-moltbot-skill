---
name: lobster-jobs
description: Create, run, and manage Lobster workflows. Transform OpenClaw cron jobs into deterministic, approval-gated workflows with resume capabilities. Use when: 'convert cron to lobster', 'create lobster workflow', 'run lobster workflow', 'check lobster status', 'migrate automation to lobster'. NOT for managing OpenClaw cron jobs directly (use cron tool).
metadata:
  openclaw:
    emoji: 🦞
    requires:
      bins: ["openclaw", "python3"]
---

# lobster-jobs

Transform OpenClaw cron jobs into Lobster workflows with approval gates, resumable execution, retries, timeouts, and native workflow composition.

## Lobster Workflow Notes

- Use a workflow file when the job needs typed handoff, approval gates, resumability, per-step retry/timeout policy, parallel fan-out, item loops, or sub-workflow composition.
- For deterministic one-command jobs, keep the wrapper as small as possible and do not bury the command inside an extra model-mediated layer.
- For Telegram delivery in workflows, use a supported delivery command such as `openclaw message send` or `openclaw.invoke --tool message --action send`; validate `channel + recipient` before sending.
- Source `scripts/lib/delivery-preflight.sh` before any send step that targets a recipient.
- Keep fallback text explicit and validate with a real chat delivery test before declaring success.
- Use `pipeline: llm.invoke` for model-backed steps; `llm_task.invoke` is compatibility-only.
- Use `$step.stdout`, `$step.json`, `$step.approved`, `$step.skipped`, `$step.error`, and `$step.errorMessage` for step references. Do not use old `$step.output` references.
- `capture:` is a legacy convention in older workflows; current Lobster ignores it at runtime.
- `condition` and `when` support booleans, approval/skipped/error references, equality/inequality, numeric comparisons (`<`, `<=`, `>`, `>=`), and boolean operators (`!`, `&&`, `||`) in current Lobster builds. For shell predicates such as `jq -e`, put the predicate in its own command step and branch on that step's result.
- Prefer native controls for execution mechanics:
  - `timeout_ms` for bounded external calls
  - `retry: { max, delay_ms, backoff, max_delay_ms, jitter }` for transient infrastructure/provider failures after the step is idempotent
  - `on_error: stop|continue|skip_rest` when follow-up steps intentionally inspect error state
  - `parallel: { wait: all|any, branches: [...] }` for independent branch work
  - `for_each: $step.json` plus nested `steps:` for array processing
  - `workflow:` with `workflow_args:` for reusable sub-workflows
- Keep domain idempotency, delivery safety, state repair, and shape normalization in tested scripts when workflow syntax alone is not enough.

## Purpose

OpenClaw cron jobs are either:
- **systemEvent**: Simple shell commands (fully deterministic)
- **agentTurn**: Natural language instructions spawning AI agents (flexible but token-heavy)

Lobster workflows offer:
- **Deterministic execution**: No LLM re-planning each step
- **Approval gates**: Hard stops requiring explicit user approval
- **Stateful execution**: Remembers cursors/checkpoints
- **Resumability**: Pauses and resumes exactly where left off
- **Reliability controls**: Native retries, step timeouts, and explicit error policy
- **Composition**: Native parallel branches, per-item loops, and sub-workflows

This skill helps analyze existing cron jobs and transform them into Lobster workflows.

## Commands

### Tier 1 (Available Now)

#### `lobster-jobs list`
List all cron jobs with their Lobster readiness score.

Output categories:
- ✅ **Fully Migratable**: Simple shell commands (systemEvent)
- 🟡 **Partial Migration**: Mixed deterministic + LLM steps (agentTurn)
- ❌ **Not Migratable**: Heavy LLM reasoning required

#### `lobster-jobs inspect <job-id>`
Inspect a specific cron job with detailed migration assessment.

Shows:
- Job metadata (schedule, target, payload type)
- Lobster migration status and reason
- Payload preview
- Migration recommendation

#### `lobster-jobs validate <workflow-file>`
Validate a Lobster workflow YAML file with lightweight local checks.

Checks:
- Required fields (name, steps)
- Step structure (id, command)
- Approval gate syntax
- Condition syntax

This is not a full runtime schema check. For generated or migrated workflows, also run a harmless runtime smoke test with the installed Lobster CLI before enabling cron.

### Tier 2 (Available Now)

#### `lobster-jobs convert <job-id>`
Transform a cron job into a Lobster workflow.

```bash
lobster-jobs convert 17fe68ca
lobster-jobs convert 17fe68ca --output-dir ~/workflows
lobster-jobs convert 17fe68ca --force  # Overwrite existing
```

Generates:
- `.lobster` workflow file in `~/.lobster/workflows/`
- Extracts commands from systemEvent or agentTurn payloads
- Auto-validates generated workflow

Options:
- `--output-dir, -o`: Custom output directory
- `--force, -f`: Overwrite existing workflow
- `--keep-on-error`: Keep file even if validation fails

#### `lobster-jobs new <name>`
Create a new Lobster workflow from scratch using templates.

```bash
lobster-jobs new my-workflow
lobster-jobs new my-workflow --template with-approval
lobster-jobs new my-workflow --template stateful
```

Templates:
- `simple-shell`: Basic command execution
- `with-approval`: Approval gate workflow
- `stateful`: Workflow with cursor/state tracking

## Installation

```bash
# Add to PATH
export PATH="$PATH:/home/art/niemand/skills/lobster-jobs/bin"

# Or create symlink
ln -s /home/art/niemand/skills/lobster-jobs/bin/lobster-jobs ~/.local/bin/
```

## Quick Start

```bash
# See all your cron jobs and their migration status
lobster-jobs list

# Inspect a specific job
lobster-jobs inspect 17fe68ca

# Convert a job to Lobster workflow
lobster-jobs convert 17fe68ca

# Create a new workflow from template
lobster-jobs new my-workflow --template with-approval

# Validate a workflow file
lobster-jobs validate ~/.lobster/workflows/my-workflow.lobster
```

## Running Workflows

### Basic Execution
```bash
# Run a workflow
lobster run --file ~/.lobster/workflows/my-workflow.lobster

# Run in tool mode (JSON output, for automation)
lobster run --file ~/.lobster/workflows/my-workflow.lobster --mode tool
```

### Approval Gates & Resume

When a workflow hits an approval gate, it halts and outputs a `resumeToken`.

**Step 1: Run workflow (halts at approval, outputs token)**
```bash
lobster run --file /path/to/workflow.lobster --mode tool
# Output includes: "resumeToken": "eyJ..."
```

**Step 2: Resume after approval**
```bash
# Approve and continue
lobster resume --token <resumeToken> --approve yes

# Reject and cancel
lobster resume --token <resumeToken> --approve no
```

**⚠️ Common Mistake:** `lobster run --resume` does NOT exist. The `--resume` flag is silently ignored. Always use the separate `lobster resume` command.

### State Files

Workflow state is saved to `~/.lobster/state/workflow_resume_<uuid>.json` when halted at an approval gate. These can be inspected for debugging:
```bash
cat ~/.lobster/state/workflow_resume_*.json | jq .
```

## Systemd Timer Notes

When Lobster workflows are triggered by systemd user timers, do not rely on interactive shell PATH.

- Use `/run/current-system/sw/bin/env` instead of `/usr/bin/env` in `ExecStart`.
- Set an explicit PATH in the service unit so `node`, `bash`, and tools resolve.
- Prefer absolute shell paths in scripts (e.g., `/run/current-system/sw/bin/bash`).

Example service snippet:

```ini
[Service]
Type=oneshot
WorkingDirectory=/home/art/niemand/skills/lobster
Environment="PATH=/run/wrappers/bin:/run/current-system/sw/bin:/home/art/.nix-profile/bin:/home/art/.npm-packages/bin:/home/art/.local/bin:/home/art/.bun/bin:/home/art/go/bin:/usr/bin:/bin"
ExecStart=/run/current-system/sw/bin/env node ./bin/lobster.js run --file /home/art/projects/lobster-workflows/workflows/my-workflow.lobster
```

## Workflow File Format

```yaml
name: my-workflow
description: Optional description

steps:
  - id: fetch_data
    command: some-cli fetch --json
    timeout_ms: 30000

  - id: fetch_retryable_data
    command: some-idempotent-cli fetch --json
    retry:
      max: 3
      delay_ms: 1000
      backoff: exponential

  - id: process
    command: some-cli process
    stdin: $fetch_data.stdout
    on_error: stop

  - id: approve_send
    approval: "Send notification?"

  - id: send
    command: openclaw message send --channel telegram --target "-1001234567890" --message "$PROCESS_STDOUT"
    env:
      PROCESS_STDOUT: $process.stdout
    condition: $approve_send.approved
```

### Native Reliability & Composition Examples

Bound a flaky provider call and continue into an explicit fallback path:

```yaml
steps:
  - id: fetch_provider
    command: bash /path/to/fetch-provider.sh
    timeout_ms: 45000
    retry:
      max: 3
      delay_ms: 1000
      backoff: exponential
      jitter: true
    on_error: continue

  - id: fallback
    command: bash /path/to/fallback.sh
    condition: $fetch_provider.error == true
```

Run independent collectors in parallel and combine their JSON:

```yaml
steps:
  - id: collect
    parallel:
      wait: all
      branches:
        - id: crm
          command: bash /path/to/crm.sh
        - id: calendar
          command: bash /path/to/calendar.sh

  - id: merge
    command: jq -n --argjson crm "$CRM" --argjson calendar "$CALENDAR" '{crm: $crm, calendar: $calendar}'
    env:
      CRM: $crm.stdout
      CALENDAR: $calendar.stdout
```

Process an array with `for_each` when each item is independent:

```yaml
steps:
  - id: list_items
    command: bash /path/to/list-items.sh

  - id: process_each
    for_each: $list_items.json
    batch_size: 5
    pause_ms: 250
    steps:
      - id: process
        command: bash /path/to/process-item.sh
        env:
          ITEM_JSON: $item.json
```

## Migration Strategy

### Wrapper Approach (Recommended)
Keep cron as scheduler, change payload to call Lobster:

```json
{
  "payload": {
    "kind": "systemEvent",
    "text": "lobster run --file ~/.lobster/workflows/my-workflow.lobster"
  }
}
```

Benefits:
- Rollback is trivial (revert payload)
- Incremental migration
- Cron scheduling already works

## Handling LLM Judgment

For jobs needing both deterministic steps and LLM reasoning:

```yaml
steps:
  - id: gather
    command: gh issue list --json title,body

  - id: triage
    pipeline: llm.invoke --provider openclaw --prompt "Classify these issues by urgency"
    stdin: $gather.stdout

  - id: notify
    command: openclaw message send --channel telegram --target "-1001234567890" --message "$TRIAGE_STDOUT"
    env:
      TRIAGE_STDOUT: $triage.stdout
```

The workflow is deterministic; the LLM is a black-box step.

## Edge Cases

| Issue | Handling |
|-------|----------|
| **Idempotency** | Workflows track step completion; restart-safe |
| **Approval timeouts** | Configurable timeout with default action |
| **Secret handling** | Environment variables or 1Password refs |
| **Partial failures** | `convert` validates before writing |

## References

- Lobster: https://github.com/openclaw/lobster
- Lobster VISION: https://github.com/openclaw/lobster/blob/main/VISION.md
