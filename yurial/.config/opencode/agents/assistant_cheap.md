---
color: "#00FF00"
description: "Cheapest executor for simple, well-specified tasks: single-file edits by exact instruction, small scripts, formatting, searching with given patterns, mechanical refactors. Handles short unambiguous instructions; not for design or debugging."
mode: subagent
model: vk-zai-personal/cheap
variant: smart
permission:
  "*": allow
  bash:
    "*": allow
    "sleep*": deny
  task: deny
prompt: "{file:./rules/assistant.md}"
---