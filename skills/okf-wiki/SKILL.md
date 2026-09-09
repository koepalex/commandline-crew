---
name: okf-wiki
description: "Create, update, preview, and validate Open Knowledge Format v0.1 LLM wiki bundles from workspace evidence, local files, and user-specified URLs using deterministic tooling."
user-invocable: true
argument-hint: "{create|update|validate|preview} [bundle=...] [sources=...]"
---

# OKF Wiki

Curate Open Knowledge Format v0.1 concepts from evidence. The bundled .NET
tool owns YAML parsing, safe writes, identity matching, generated indexes and
logs, dry-run planning, and validation.

## Prerequisites and safety

- Require the .NET 10 SDK and first-build NuGet access for pinned YamlDotNet.
- Require write access for create and update.
- If .NET or restore is unavailable, report the concise error. Never replace
  the tool with handwritten YAML parsing or manual generated-file edits.
- Do not invent facts, types, resource URIs, schema details, or citations.
- Never put credentials, tokens, secrets, or sensitive source content in an
  operation manifest.

## Intent

| Intent | Behavior |
|---|---|
| `create` | Create one or more concepts. |
| `update` | Update by concept path, or by one unique resource URI when no path is supplied. |
| `preview` / `dry run` | Plan create or update without writes. |
| `validate` | Validate a bundle without changing it. |

Natural-language equivalents count.

## Essential workflow

1. Resolve the operation, bundle, sources, concept scope/path, and metadata.
2. For writes without a bundle path, propose `./llm-wiki` and obtain explicit
   confirmation. If clarification is unavailable, request an explicit path and
   stop.
3. Gather the smallest relevant evidence and separate fact from interpretation.
4. Plan concept path, type, title, description, resource, tags, body, and
   citations.
5. Build a JSON operation manifest outside the target bundle.
6. Invoke the bundled deterministic tool. Use dry-run for preview.
7. Validate after every successful non-preview write.
8. Remove the temporary manifest and report exact changes, warnings, or
   diagnostics.

**Read
[`references/okf-rules-and-planning.md`](references/okf-rules-and-planning.md)
before planning or writing concepts.** It defines bundle rules, identity,
clarification, evidence, and concept design.

**Read
[`references/manifest-and-tool.md`](references/manifest-and-tool.md) before
creating a manifest or invoking the tool.** It contains the manifest schema,
cross-platform commands, deterministic behavior, validation, and reporting.

**Read
[`references/troubleshooting.md`](references/troubleshooting.md) whenever a
tool, identity, existing concept, YAML, or validation failure occurs.**

Dependency attribution is in
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).
