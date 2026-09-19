---
color: "#FF00FF"
description: "Executor on keydealer/gpt-6-astra that strictly follows given instructions. Invoke ONLY when the user explicitly asks for assistant_astra (e.g. @assistant_astra); NEVER invoke it proactively or automatically."
mode: subagent
model: keydealer/gpt-6-astra
permission:
  "*": allow
  bash:
    "*": allow
    "sleep*": deny
  task:
    "*": deny
prompt: "{file:./rules/assistant.md}"
---
