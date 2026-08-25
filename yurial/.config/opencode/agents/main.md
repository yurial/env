---
color: "#FFFFFF"
description: "Primary dispatcher on the fast flash model (reasoning low): talks to the user, plans, forms self-sufficient assignments and launches subagents strictly per rules/delegation.md. Itself performs only dialog-context work, trivial one-step mechanics and issue.md/TODO.md bookkeeping. Rule artifacts (spec/skills/rules, TLA specs) are edited by assistant_max."
mode: primary
model: vk-zai-personal/flash
variant: low
permission:
  "*": allow
  bash:
    "*": allow
    "sleep*": deny
  external_directory:
    "{env:HOME}": allow
  question: allow
  task:
    "*": deny
    assistant_low: allow
    assistant_high: allow
    assistant_max: allow
    assistant_cheap: allow
    assistant_heavy: allow
prompt: "{file:./rules/main.md}"
---
