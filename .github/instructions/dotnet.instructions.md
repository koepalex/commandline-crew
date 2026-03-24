---
applyTo: "**/*.cs,**/*.csproj,**/*.sln,**/*slnx"
---

# .NET / C# Coding Instructions

## Target Stack
- Framework: .NET 10.0
- Language: C# 14 with nullable reference types enabled
- Test framework: xUnit with NSubstitute

## Design
- Design public interfaces (with XML docs) before writing implementations.
- Follow SOLID and GRASP principles; prefer composition over inheritance.
- Use Dependency Injection via `Microsoft.Extensions.DependencyInjection`; never use the Service Locator pattern.
- Choose DI lifetimes deliberately: `Singleton` for stateless/thread-safe, `Scoped` for per-request, `Transient` for lightweight stateful.
  - Constructor injection is the default
  - Use factory patterns only when necessary

## C# Style
- PascalCase for public members; camelCase (optionally `_`-prefixed) for private fields.
- True constants in `SCREAMING_SNAKE_CASE`.
- Prefer `record` / `record struct` for immutable DTOs.
- Use `required` and `init` properties instead of mutable setters where possible.
- Use primary constructors for simple service classes.
- Use collection expressions `[..]` instead of `new List<T> { }`.
- Use raw string literals for multi-line strings (JSON, SQL, regex).
- Use file-scoped `namespace` declarations.
- Suffix async methods with `Async` only when there is a synchronous sibling.

## Logging
- Use `ILogger<T>` for structured logging

## Async/Await
- Never block with `.Result` or `.Wait()`; always `await`.
- Use `ConfigureAwait(false)` in library/non-UI code.
- Use `ValueTask<T>` for hot paths that usually complete synchronously.
- Always accept and propagate `CancellationToken`; default to `= default`.
- Never use `async void` except for event handlers.
- Handle cancellation tokens correctly
- Use `IAsyncEnumerable<T>` for streaming responses

## Performance
- Prefer `Span<T>` / `ReadOnlySpan<T>` over array copies for short-lived data.
- Return `IReadOnlyCollection<T>` / `IReadOnlyList<T>` instead of `IEnumerable<T>` when count is needed.
- Use `StringBuilder` for 3+ string concatenations.
- Use `LoggerMessageAttribute` for structured, source-generated logging; never use string interpolation inside `ILogger` calls.
- Return empty collections, never `null`.

## Error Handling
- Throw exceptions only for truly exceptional conditions.
- Include meaningful context in exception messages.
- Create custom exception types only when callers need to catch them specifically.
- Never swallow exceptions silently.
- Document thrown exceptions in XML `<exception>` tags.

## Comments
- Comment **why**, not what.
- XML documentation on all public APIs only.
- No noise comments (e.g., `// Set x to 5`).

## NuGet Packages
- MIT-licensed packages only.
- Always target the latest stable version.
- Prefer built-in .NET APIs over third-party packages when equivalent.

## Testing
- Write tests against the public interface, not the implementation.
- Use Arrange / Act / Assert structure.
- Use `[Theory]` + `[InlineData]` for parameterized edge cases.
- Mock interfaces, not concrete classes.