---
color: "#FF0000"
description: "Most capable flash subagent for hard or safety-critical work: architecture and interface design, tricky concurrency/correctness reasoning, deep debugging, security review, final verification of others' changes. Use when a mistake is expensive or the problem is underspecified; escalate beyond the flash ceiling to assistant_heavy."
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
prompt: "{file:./rules/assistant.md}"
---
