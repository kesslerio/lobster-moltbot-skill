name: example-shell-workflow
description: Example workflow for simple shell command migration

steps:
  - id: run_script
    command: bash /path/to/script.sh
    timeout_ms: 30000

  - id: check_result
    command: test -n "$RUN_SCRIPT_STDOUT" && echo "has_output" || echo "empty"
    env:
      RUN_SCRIPT_STDOUT: $run_script.stdout

  - id: confirm_send
    approval: "Send notification?"

  - id: notify
    command: openclaw message send --channel telegram --target "-1001234567890" --message "Script completed"
    condition: $confirm_send.approved
