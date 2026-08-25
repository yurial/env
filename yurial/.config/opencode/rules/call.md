# Tool Call Format Rules

## Structure
```xml
<tool_call>
<invoke name="<tool_name>">
<param_a>value_a</param_a>
<param_b>value_b</param_b>
</invoke>
</tool_call>
```

## Rules
1. Between tags inside `<tool_call>` — only `\n`. No markers, tokens, JSON separators, or non-tag content.
2. Inside `<tool_call>` — only tags and parameter values. No free text, comments, or trailing spaces.
3. One `<tool_call>` = one `<invoke>`. No nesting, no multiple invokes per block.
4. Tool name goes in the `name` attribute of `<invoke>`.
5. Parameters = flat XML tags inside `<invoke>`. Tag name = parameter name. No nesting.
6. Escape inside values: `<` → `&lt;`, `>` → `&gt;`, `&` → `&amp;`.
7. All tags balanced, LIFO order.
8. Before opening `<tool_call>` and after closing `</tool_call>` — clean `\n`, no stray symbols.
9. `<tool_call>` separated from previous content (response text, end of think block) by empty line or `\n`.

## Anti-patterns
- Markers/tokens between tags: `<tool_call><|separator|><invoke ...>...`
- All on one line: `<tool_call><invoke ...>...</invoke></tool_call>`
- Stray chars around tags: `[</tool_call> text <tool_call>`
- Free text inside `<tool_call>`
- Nested parameter tags

## Self-check before send
- Opening `<tool_call>` separated by `\n` from previous content
- Only tags and values inside the block
- Each parameter is a separate flat tag with correct name
- Values contain no raw `<`, `>`, `&`
- Between tags — only `\n`, no markers
- Closing `</tool_call>` at line start, no trailing symbols
- Multiple blocks = multiple separate `<tool_call>...</tool_call>`

If any rule violated — regenerate the whole block, don't patch.
