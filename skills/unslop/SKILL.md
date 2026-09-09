---
name: unslop
description: "Rewrite human-facing prose to sound natural, direct, and deliberate while preserving meaning, facts, technical accuracy, audience, and tone. Use for documentation, release notes, pull requests, issues, email, articles, reports, and explanations. Do not alter code, commands, identifiers, quoted source text, or required templates unless explicitly asked."
user-invocable: true
argument-hint: "[text, file, or writing task]"
---

# Unslop

Remove generated-sounding filler without changing what the author means.

## Essential workflow

1. Identify the audience, purpose, and intended tone.
2. Find vague, inflated, repetitive, formulaic, or needlessly complex prose.
3. Rewrite with concrete nouns, active verbs, plain words, and varied natural
   sentence lengths.
4. Preserve facts, constraints, citations, uncertainty, and domain terms.
5. Remove any remaining sentence that could fit unchanged into unrelated
   documentation.

Return only the revised text unless the user asks for commentary or a change
list.

## Non-negotiable preservation rules

- Keep code, commands, paths, URLs, identifiers, API names, versions,
  citations, quoted text, legal or standards terminology, product names, and
  required templates exact.
- Do not invent sources, measurements, actors, praise, causal explanations, or
  certainty.
- When editing a file, change prose only unless the request explicitly includes
  examples or generated content.

**Read [`references/rewrite-rules.md`](references/rewrite-rules.md) before
rewriting.** It contains the full list of empty, formulaic, weak, and
generated-sounding constructions to remove.

**Read [`references/final-check.md`](references/final-check.md) before returning
the result.** It contains the required accuracy and quality checklist.

## Attribution

This adaptation is based on the ideas in Cursor's
[`unslop` skill](https://github.com/cursor/plugins/blob/main/pstack/skills/unslop/SKILL.md).
These instructions are rewritten for use across supported agent runtimes.
