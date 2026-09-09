# OKF rules and planning

## Inputs and defaults

| Input | Requirement and default |
|---|---|
| `bundle` | Local directory. For writes, propose `./llm-wiki` and confirm when omitted. |
| `sources` | Optional workspace paths, local files, and URLs. The workspace remains available as evidence. |
| `conceptPath` | Required before create, but may be derived from scope. Preferred update identity. |
| `resource` | Optional canonical URI; update identity only when no concept path is supplied. |
| `dry-run` | Preview flag; defaults to false. |

Paths may use the host platform's separators. Prefer forward slashes in
documentation and bundle-relative concept paths.

- Bundle paths are local directories.
- Validation may inspect an explicitly named existing bundle without write
  confirmation.
- For updates, use explicit `conceptPath` first. Otherwise `resource` must
  match exactly one concept. Never guess from title, filename, or body.
- Ask when decomposition, path, type, resource identity, or overwrite intent
  remains materially ambiguous.
- Preview unfamiliar bulk updates or changes likely to replace curated index
  organization.

## Non-negotiable OKF rules

1. Concepts are UTF-8 Markdown files with YAML frontmatter beginning at byte
   zero.
2. Every concept has a non-empty `type`.
3. `index.md` and `log.md` are reserved and cannot be concept paths.
4. Unknown types and producer-defined frontmatter fields are allowed.
5. Preserve unknown frontmatter fields during update.
6. Broken cross-links do not invalidate a bundle.
7. Prefer bundle-relative links beginning with `/`.
8. Use structural Markdown and conventional `# Schema`, `# Examples`, and
   `# Citations` sections when applicable.
9. Put citations for source-derived factual claims in a final `# Citations`
   section.
10. Do not invent facts, types, resource URIs, schema details, or citations.

## Gather evidence

- Inspect the smallest relevant workspace scope first.
- Read explicitly supplied files before broad searches.
- Fetch explicitly supplied URLs with approved web tools.
- Do not send private workspace content to third-party services.
- Record source paths and URLs needed for citations.
- Separate observations from interpretation and omit unsupported claims.

## Plan concepts

For each concept determine:

- bundle-relative path, with or without `.md`;
- descriptive, self-explanatory `type`;
- title and one-sentence description;
- canonical `resource` URI when one exists;
- concise tags;
- structured Markdown body;
- citations.

For multiple concepts, present a compact path/type/title mapping. Clarify only
unresolved semantic choices, and do not impose a fixed taxonomy.
