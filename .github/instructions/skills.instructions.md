---
applyTo: "skills/**"
---

# Skill authoring instructions

## Structure and naming

- Use a kebab-case skill folder and matching kebab-case `name` in frontmatter.
- Every skill has `SKILL.md` and a `references/` directory when detailed
  guidance is needed.
- Keep optional tools and scripts inside the skill directory so installers can
  copy the skill as one unit.

## Portable frontmatter

- `name` and `description` are the shared contract and must be valid YAML
  understood by both GitHub Copilot and OpenCode.
- Write a specific activation-oriented `description` that states when to use
  the skill and important exclusions.
- Copilot-specific optional metadata such as `user-invocable` and
  `argument-hint` may remain only when other runtimes can safely ignore it.

## Progressive disclosure

Keep `SKILL.md` concise. It must contain:

- frontmatter;
- activation and purpose;
- safety-critical or non-negotiable constraints;
- the essential workflow;
- explicit relative Markdown links to reference files, stating when each
  reference must be read.

Move detailed procedures, schemas, examples, command catalogs,
troubleshooting, and extended rationale into logically named
`references/*.md` files. Preserve substantive behavior when modularizing.
Reference files must be usable from the skill directory and must not rely on
repository-root-relative links.

## Runtime compatibility

- Describe capabilities rather than assuming tool names when guidance is
  shared across runtimes.
- Add a concise tool-name or capability mapping when Copilot and OpenCode use
  different names.
- Gate runtime-specific commands, launchers, paths, state stores, and artifacts
  explicitly. A runtime may use portable guidance without pretending
  compatibility with another runtime's integration.
- Prefer cross-platform paths and commands. Where syntax differs, provide
  separate examples or a shell-neutral single-line form.

## Safety, attribution, and scope

- Keep safety boundaries in `SKILL.md`; detailed allow/deny lists may live in a
  required reference.
- Keep scripts, executable tools, manifests, and optional assets within the
  skill folder.
- Preserve upstream attribution and license notices. Link to
  `THIRD-PARTY-NOTICES.md` when present.
- Update repository documentation or tests only when the skill change requires
  it. Do not make unrelated edits.

## Validation checklist

Before completing a skill change, verify:

1. Folder and frontmatter names match and use kebab-case.
2. Frontmatter parses as YAML and has portable `name` and `description`.
3. `SKILL.md` contains purpose, activation, safety, essential workflow, and
   explicit relative reference links with read conditions.
4. Every linked reference and local tool/script path exists.
5. Detailed behavior was moved, not dropped or contradicted.
6. Runtime-specific behavior is clearly gated and tool names are mapped where
   needed.
7. Commands and path examples are cross-platform where practical.
8. Attribution and notices remain intact.
9. Only necessary documentation or tests were changed.
