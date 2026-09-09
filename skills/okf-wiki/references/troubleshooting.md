# Troubleshooting

- If .NET 10 is unavailable, report that the skill requires the .NET 10 SDK.
  Do not replace the parser with ad hoc YAML handling.
- If restore or compilation fails, surface the concise `dotnet` error.
- If the tool exits without its documented JSON result, report an unexpected
  tool failure and do not claim apply or validation completed.
- If a concept exists during create, ask whether to update. Never switch
  actions silently.
- If update identity is missing or ambiguous, request an explicit concept path.
- If existing YAML is invalid, do not rewrite it. Report validation details.
- Never hand-edit generated `index.md` or `log.md` after a tool failure.
- Stop a multi-concept operation on its first failure and report which earlier
  operations, if any, succeeded.
