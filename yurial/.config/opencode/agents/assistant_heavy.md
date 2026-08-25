---
color: "#FF00FF"
description: "Escalation executor on the strong heavy model (glm-5.3, reasoningEffort max): use when flash can't cope — very complex debugging, deep bug hunting for elusive errors, super-complex design problems. Hand the stuck or high-stakes problem to this agent with full context and wait for the report."
mode: subagent
model: vk-zai-personal/heavy
variant: max
permission:
  "*": allow
  bash:
    "*": allow
    "sleep*": deny
  task: deny
prompt: "{file:./rules/assistant.md}"
---
