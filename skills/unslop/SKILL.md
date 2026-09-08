---
name: unslop
description: "Rewrite human-facing prose to remove common AI-writing tells while preserving meaning, facts, technical accuracy, and the intended tone. Use when drafting or editing documentation, README content, release notes, pull request descriptions, issue text, emails, articles, reports, explanations, or other prose. Also use when the user asks to make text sound natural, direct, concise, plain-spoken, less robotic, or less AI-generated. Do not alter code, commands, identifiers, quoted source text, or required templates unless the user explicitly asks."
user-invocable: true
argument-hint: "[text, file, or writing task]"
---

# Unslop

Edit prose so it reads like deliberate human writing instead of generated
filler. Keep the author's meaning, facts, audience, and tone.

This Copilot adaptation is based on the ideas in Cursor's
[`unslop` skill](https://github.com/cursor/plugins/blob/main/pstack/skills/unslop/SKILL.md).
The instructions here are rewritten for GitHub Copilot CLI.

## Process

1. Identify the audience, purpose, and intended tone.
2. Mark phrases that are vague, inflated, repetitive, formulaic, or harder to
   parse than necessary.
3. Rewrite with concrete nouns, active verbs, plain words, and natural sentence
   lengths.
4. Preserve facts, constraints, citations, and domain terminology.
5. Read the result once more and remove any remaining sentence that could fit
   unchanged into unrelated documentation.

Return only the revised text unless the user asks for commentary or a list of
changes.

## What to remove

### Empty content

- Delete unsupported claims such as "experts agree" or "research shows." Name
  the source when one exists.
- Replace broad benefits with the mechanism, instruction, measurement, or
  consequence that makes the claim true.
- Remove generic introductions and conclusions that add no information.
- Do not add praise, reassurance, or enthusiasm that the author did not express.

### Formulaic language

- Replace stock transitions such as "additionally," "it is important to note,"
  and "in order to" with a direct sentence.
- Avoid fashionable words when a plain term works. Examples include "delve,"
  "pivotal," "landscape," "tapestry," "showcase," "leverage," and "utilize."
- Prefer "is" and "has" over inflated substitutes such as "serves as,"
  "stands as," "boasts," and "features."
- State the point directly instead of using "not just X, but Y."
- Do not force ideas into groups of three.
- Use one stable term for a concept instead of cycling through synonyms.
- Use "from X to Y" only when X and Y form a real range.

### Generated-sounding style

- Avoid em dashes. Use a period or comma.
- Use colons for lists or examples, not as a routine sentence connector.
- Use sentence case for headings.
- Do not decorate headings or bullets with emojis.
- Use bold text only when it helps the reader scan.
- Avoid list items whose bold label merely repeats the sentence after it.
- Use straight quotes unless the target style requires typographic quotes.
- Remove chatbot phrases such as "Certainly," "Great question," "I hope this
  helps," and "Let me know if."

### Weak construction

- Prefer active voice when the actor matters or is known.
- Cut adverbs that only prop up a weak verb. Use a stronger verb or a measured
  fact.
- Split sentences that contain several independent ideas.
- Use complete sentences. Do not compress prose into arrows, fragments, or
  unexplained abbreviations.
- Remove repeated qualifications. Keep only the uncertainty supported by the
  evidence.
- Replace metaphors and management jargon with the concrete action or object.

## Preserve technical accuracy

- Do not simplify away a necessary technical distinction.
- Keep code, commands, paths, URLs, identifiers, API names, version numbers,
  citations, and quoted material exact.
- Do not invent measurements, sources, actors, or causal explanations.
- Keep required terminology from standards, legal text, product names, and
  user-provided templates.
- When editing a file, change prose only. Leave code examples and generated
  content alone unless the request includes them.

## Final check

Before returning the rewrite, ask:

- Does every sentence tell this reader something specific?
- Can any abstract claim become a fact, instruction, example, or number?
- Are the sentences direct without becoming abrupt?
- Did the rewrite preserve the original meaning and level of certainty?
- Does any phrase still sound like a generic assistant response?

Fix any remaining problems, then return the text.
