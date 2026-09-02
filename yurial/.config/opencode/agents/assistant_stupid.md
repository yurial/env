---
color: "#00FF00"
description: "Cheapest executor with thinking disabled (variant stupid on glm-4.6v): same scope as assistant_cheap (single-file edits by exact instruction, small scripts, formatting, searching with given patterns, mechanical refactors) but without reasoning — for trivially predictable work; not for design or debugging."
mode: subagent
model: vk-zai-personal/cheap
variant: stupid
permission:
  "*": allow
  bash:
    "*": allow
    "sleep*": deny
  task: deny
prompt: "{file:./rules/assistant.md}"
---
