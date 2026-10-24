---
color: "#00FF00"
description: "Cheap executor for simple, well-specified tasks: single-file edits by exact instruction, small scripts, formatting, searching with given patterns, mechanical refactors. Handles short unambiguous instructions; not for design or debugging."
mode: subagent
model: myzai/flash
variant: high
permission:
  "*": allow
  bash:
    "*": allow
    "sleep*": deny
  task:
    "*": deny
    assistant_low: allow
    assistant_high: allow
    assistant_max: allow
    assistant_heavy: allow
prompt: "{file:./rules/assistant.md}"
---
