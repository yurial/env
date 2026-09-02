---
color: "#00FF00"
description: "Cheap flash executor with thinking disabled: same scope as assistant_low (simple, well-specified tasks: single-file edits by exact instruction, small scripts, formatting, searching with given patterns, mechanical refactors) but without reasoning — fastest and cheapest flash option for trivially predictable work; not for design or debugging."
mode: subagent
model: vk-zai-personal/flash
variant: stupid
permission:
  "*": allow
  bash:
    "*": allow
    "sleep*": deny
  task: deny
prompt: "{file:./rules/assistant.md}"
---
