# Manifest and deterministic tool

## Operation manifest

Create a temporary JSON file in an approved runtime scratch location outside
the target bundle. Prefer the operating system's temporary directory outside
the repository. If policy confines artifacts to an approved workspace path,
use that path while keeping the manifest outside the target bundle.

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

Rules:

- `action` is `create` or `update`.
- Create requires `conceptPath`, which may be derived from the knowledge scope.
- Update uses `conceptPath` when supplied; otherwise use `matchResource`.
- Omit known fields on update to preserve current values.
- Use `removeFields` to intentionally remove optional metadata.
- `metadata` contains only producer-defined fields, not `type`, `title`,
  `description`, `resource`, `tags`, or `timestamp`.
- Omit `timestamp` unless supplied by the user. The tool assigns current UTC
  after a meaningful change.
- Omit `body` on update to preserve it.
- Do not include secrets or sensitive source content.

## Tool location

Resolve the installed skill directory from the runtime. The project is:

```text
tool/OkfWiki.Tool/OkfWiki.Tool.csproj
```

Do not copy it elsewhere. Let `dotnet` restore the pinned dependency.

## Cross-platform commands

These single-line commands work in PowerShell, Bash, and most command shells
when the placeholders are replaced with native paths:

```text
dotnet run --project "<skill-directory>/tool/OkfWiki.Tool/OkfWiki.Tool.csproj" -- apply --bundle "<bundle-path>" --manifest "<manifest.json>"
dotnet run --project "<skill-directory>/tool/OkfWiki.Tool/OkfWiki.Tool.csproj" -- apply --bundle "<bundle-path>" --manifest "<manifest.json>" --dry-run
dotnet run --project "<skill-directory>/tool/OkfWiki.Tool/OkfWiki.Tool.csproj" -- validate --bundle "<bundle-path>" --json
```

Supported CLI forms:

```text
apply --bundle <path> --manifest <json> [--dry-run]
validate --bundle <path> [--json]
```

The tool writes JSON to standard output, concise failures to standard error,
and returns non-zero for invalid input or bundles.

For multiple concepts, apply one manifest at a time in dependency order. Stop
on the first failure and do not claim the batch completed.

## Deterministic behavior

The tool:

- rejects rooted, traversing, and reserved concept paths;
- preserves unknown YAML fields and nested values;
- rejects ambiguous resource matches;
- regenerates the changed directory's `index.md` and each ancestor index;
- appends root and concept-directory `log.md` history, writing once when they
  are the same file;
- reports created, updated, and unchanged files as JSON;
- writes nothing in dry-run mode.

## Validate and report

After all successful non-preview operations, run validation. Do not report
completion when the command returns non-zero or `isValid: false`. Surface
actionable path/code diagnostics.

Validation intentionally permits unknown types and fields, missing optional
fields, broken cross-links, and absent index files in pre-existing bundles.

Delete temporary manifests after the tool finishes. Report:

- bundle path;
- concise counts and paths for concepts, indexes, and logs;
- every warning, including post-commit cleanup warnings;
- for preview, that no files were written;
- for unchanged update, that no meaningful change was detected;
- for validation, valid/invalid first, followed only by actionable diagnostics.

Do not misreport an applied operation as failed solely because cleanup emitted
a warning.
