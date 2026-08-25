---
color: "#FF0000"
description: "Most capable subagent for hard or safety-critical work: architecture and interface design, tricky concurrency/correctness reasoning, deep debugging, security review, final verification of others' changes. Use when a mistake is expensive or the problem is underspecified."
mode: subagent
model: vk-zai-personal/flash
variant: max
permission:
  "*": allow
  bash:
    "*": allow
    "sleep*": deny
  task: deny
prompt: "{file:./rules/assistant.md}"
---
