---
color: "#FFFF00"
description: "Mid-cost developer for standard subtasks: multi-file feature work from a clear plan, writing tests to a given spec, debugging with reproduction, code review of moderate scope. Balanced default when the task is concrete but needs some judgment."
mode: subagent
model: vk-zai-personal/flash
variant: high
permission:
  "*": allow
  bash:
    "*": allow
    "sleep*": deny
  task: deny
prompt: "{file:./rules/assistant.md}"
---
