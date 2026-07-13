---
name: okf-wiki
description: "Create, update, preview, and validate OKF/Open Knowledge Format LLM wikis with deterministic tooling."
user-invocable: true
argument-hint: "{create|update|validate|preview} [bundle=...] [sources=...]"
---

# OKF Wiki

## Overview

Create and maintain Open Knowledge Format v0.1 bundles from workspace evidence,
explicit local files, and user-specified URLs. You own semantic curation; the
bundled .NET tool owns YAML parsing, safe writes, identity matching, generated
indexes/logs, dry-run planning, and conformance validation.

## Prerequisites

* .NET 10 SDK available through `dotnet`.
* Write access to the selected bundle for create and update operations.
* NuGet access on the first tool build so the pinned YamlDotNet package can be
  restored.

If .NET 10 or package restore is unavailable, stop with the concise error. Do
not fall back to handwritten YAML parsing.

## Quick Start

Invoke the skill with requests such as:

```text
Create an OKF wiki from the API documentation in this repository.
Update .\knowledge using .\schemas\customer.json.
Preview adding https://example.com/runbook to .\llm-wiki.
Validate the OKF bundle at .\llm-wiki.
```

## Parameters Reference

| Intent | Behavior |
|---|---|
| `okf-wiki create ...` | Create one or more new concepts. |
| `okf-wiki update ...` | Update by explicit concept path, or by a unique `resource` URI when no path is supplied. |
| `okf-wiki validate ...` | Validate the bundle without changing it. |
| `okf-wiki preview ...` / `dry run` | Plan create/update changes with no filesystem writes. |

Natural-language equivalents count. Determine the intent from the full request;
do not require the literal command words.

| Input | Requirement and default |
|---|---|
| `bundle` | Local bundle directory. For writes, propose `.\llm-wiki` and confirm when omitted. |
| `sources` | Optional workspace paths, local files, and URLs. The current workspace remains available as evidence. |
| `conceptPath` | Must be resolved before create; derive it from the requested scope unless materially ambiguous. Preferred identity for update. |
| `resource` | Optional canonical URI; update identity only when no concept path is supplied. |
| `dry-run` | Optional preview flag; defaults to false. |

## Defaults and required clarification

* Bundle paths are always local directories.
* When the user provides no bundle path, propose `.\llm-wiki` and obtain
  explicit confirmation through the runtime's available clarification
  mechanism before any write. If interactive clarification is unavailable,
  stop and request an explicit bundle path. Validation may inspect an
  explicitly named existing bundle without confirmation.
* Use the current workspace plus any user-specified files or URLs as source
  material.
* For updates, use an explicit concept path first. Only when no path is supplied
  may `resource` be used, and it must match exactly one concept. Never guess by
  title, filename similarity, or body text.
* Ask when concept decomposition, target path, type, resource identity, or
  overwrite intent remains materially ambiguous.
* Preview before an unfamiliar bulk update or when deterministic index
  regeneration may replace curated index organization.

## Non-negotiable OKF rules

1. Concepts are UTF-8 markdown files with YAML frontmatter starting at byte
   zero.
2. Every concept has a non-empty `type`.
3. `index.md` and `log.md` are reserved and cannot be concept paths.
4. Unknown types and producer-defined frontmatter fields are allowed.
5. Preserve unknown frontmatter fields when updating.
6. Broken cross-links do not make a bundle invalid.
7. Prefer bundle-relative links beginning with `/`.
8. Use structural markdown and conventional `# Schema`, `# Examples`, and
   `# Citations` sections when applicable.
9. Factual claims from external or source material should have citations under
   a final `# Citations` section.
10. Do not invent facts, types, resource URIs, schema details, or citations.

## Workflow

### 1. Resolve the operation

Identify:

* operation: create, update, validate, or preview;
* bundle path;
* source files, workspace areas, and URLs;
* requested concept paths or the knowledge scope to decompose;
* any explicit metadata, tags, resource URIs, and body requirements.

For create/update work without an explicit bundle path, confirm `.\llm-wiki`
before continuing.

### 2. Gather evidence

* Inspect the smallest relevant workspace scope first.
* Read explicitly supplied files before broad repository searches.
* Fetch explicitly supplied URLs with approved web tools.
* Do not send private workspace content to third-party services.
* Record source paths/URLs needed for citations.
* Separate observed facts from interpretation. Omit unsupported claims.

### 3. Plan concepts

For each concept, determine:

* bundle-relative path, excluding or including the `.md` suffix;
* descriptive, self-explanatory `type`;
* title and one-sentence description;
* canonical `resource` URI when one exists;
* concise tags;
* structured markdown body;
* citations.

For multiple concepts, present a compact path/type/title mapping and clarify
only unresolved semantic choices. Do not create a fixed taxonomy.

### 4. Build an operation manifest

Create a temporary JSON file in an approved runtime scratch location outside
the target bundle. Prefer the operating system's temporary directory and a
location outside the repository. When caller or sandbox policy confines
artifacts to an approved workspace path, use that path and still keep the
manifest outside the target bundle. Use this shape:

```json
{
  "action": "create",
  "conceptPath": "tables/orders",
  "type": "BigQuery Table",
  "title": "Orders",
  "description": "One row per completed customer order.",
  "resource": "https://example.test/tables/orders",
  "tags": ["sales", "orders"],
  "metadata": {
    "owner": {
      "team": "data"
    }
  },
  "removeFields": [],
  "body": "# Schema\n\n...\n\n# Citations\n\n[1] [Source](https://example.test/source)",
  "logMessage": "Added the Orders table reference."
}
```

Manifest rules:

* `action` is `create` or `update`.
* `conceptPath` is required in a create manifest, but may be derived from the
  requested knowledge scope rather than supplied directly by the user.
* Update uses `conceptPath` when supplied; otherwise supply `matchResource`.
* Omit known fields on update to preserve their current values.
* Use `removeFields` to intentionally remove optional metadata.
* `metadata` contains only producer-defined fields; do not duplicate `type`,
  `title`, `description`, `resource`, `tags`, or `timestamp`.
* Omit `timestamp` unless the user supplied one. The tool assigns the current
  UTC timestamp after a meaningful change.
* Omit `body` on update to preserve the existing body.
* Do not place credentials, tokens, secrets, or sensitive source content in the
  manifest.

### 5. Invoke the deterministic tool

The tool project is relative to this `SKILL.md`:

```text
tool\OkfWiki.Tool\OkfWiki.Tool.csproj
```

Apply:

```powershell
dotnet run --project "<skill-directory>\tool\OkfWiki.Tool\OkfWiki.Tool.csproj" -- `
  apply --bundle "<bundle-path>" --manifest "<temporary-manifest.json>"
```

Preview:

```powershell
dotnet run --project "<skill-directory>\tool\OkfWiki.Tool\OkfWiki.Tool.csproj" -- `
  apply --bundle "<bundle-path>" --manifest "<temporary-manifest.json>" --dry-run
```

Validate:

```powershell
dotnet run --project "<skill-directory>\tool\OkfWiki.Tool\OkfWiki.Tool.csproj" -- `
  validate --bundle "<bundle-path>" --json
```

Use the exact installed skill directory supplied by the skill runtime. Do not
copy the tool elsewhere. Let `dotnet` restore its pinned YamlDotNet dependency
when required.

The tool:

* rejects rooted, traversing, or reserved concept paths;
* preserves unknown YAML fields and nested values;
* rejects ambiguous resource matches;
* regenerates the changed directory's `index.md` and every ancestor index;
* appends history to the root `log.md` and the concept directory's `log.md`,
  writing only once when they are the same file;
* returns JSON describing created, updated, or unchanged files;
* writes nothing during `--dry-run`.

For multiple concepts, invoke one manifest at a time in dependency order. Stop
on the first failure, report it, and do not claim the batch completed.

### 6. Validate after writes

After all successful non-preview operations, run `validate`. Do not report
completion when validation returns a non-zero exit code or `isValid: false`.
Surface actionable diagnostics with their paths and codes.

Validation is intentionally permissive about:

* unknown `type` values;
* unknown frontmatter fields;
* missing optional fields;
* broken cross-links;
* absent index files in pre-existing bundles.

### 7. Clean up and report

* Delete temporary manifest files after the tool finishes.
* Report the bundle path and concise counts/paths for concepts, indexes, and
  logs created or updated.
* Surface every warning returned by the tool, including post-commit cleanup
  warnings, without misreporting an applied operation as failed.
* For preview, state explicitly that no files were written.
* For unchanged updates, state that no meaningful change was detected.
* For validation, lead with valid/invalid and list only actionable diagnostics.

## Script Reference

The .NET project is self-contained under `tool\` and is copied recursively by
the repository's skill installer. Use the commands in Workflow step 5 for
normal execution. The supported CLI forms are:

```text
apply --bundle <path> --manifest <json> [--dry-run]
validate --bundle <path> [--json]
```

The tool writes JSON results to standard output, concise failures to standard
error, and uses a non-zero exit code for invalid input or invalid bundles.

## Troubleshooting

* If `.NET 10` is unavailable, stop and report that the skill requires the .NET
  10 SDK; do not replace the parser with ad hoc YAML handling.
* If restore or compilation fails, surface the concise `dotnet` error.
* If the tool terminates without its documented JSON result, report an
  unexpected tool failure and do not claim that apply or validation completed.
* If a concept already exists during create, ask whether the user wants an
  update; do not silently switch actions.
* If update identity is missing or ambiguous, ask for an explicit concept path.
* If existing YAML is invalid, do not rewrite it. Report validation details.
* Never hand-edit generated `index.md` or `log.md` as a fallback after tool
  failure.
