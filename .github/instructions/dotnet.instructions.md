---
applyTo: "**/*.cs,**/*.csproj,**/*.sln,**/*slnx"
---

# .NET / C# Coding Instructions

## Target Stack
- Framework: .NET 10.0
- Language: C# 14 with nullable reference types enabled
- Test framework: xUnit with NSubstitute

---

<!-- ═══════════════════════════════════════════════════ -->
<!-- 1. PROJECT FOUNDATION                              -->
<!-- ═══════════════════════════════════════════════════ -->

## Solution & Project Structure
- Use the `.slnx` (XML) solution format — do not use legacy `.sln` files.
- One type per file; file name must match the type name.
- Organize projects by bounded context or layer, not by technical concern alone.

## Project & Build
- Enable `<ImplicitUsings>enable</ImplicitUsings>` and `<Nullable>enable</Nullable>` in `Directory.Build.props`.
- Use Central Package Management (`Directory.Packages.props`) for consistent versions.
- Enable `<EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>` and maintain a shared `.editorconfig`.
- Enable AOT/trimming analyzers early if targeting Native AOT (`<IsAotCompatible>true</IsAotCompatible>`).

## NuGet Packages
- MIT-licensed and Apache-licensed packages only.
- Always target the latest stable version.
- Prefer built-in .NET APIs over third-party packages when equivalent.

### Preferred Packages
- Logging: `Microsoft.Extensions.Logging.Abstractions`
- JSON: `System.Text.Json` (built-in; avoid Newtonsoft for new code)
- Validation: `FluentValidation`
- Resilience: `Microsoft.Extensions.Http.Resilience`
- Results: `ErrorOr` or `OneOf` for discriminated-union-style results
- Mapping: `Riok.Mapperly`
- Caching: `Microsoft.Extensions.Caching.Hybrid`
- Telemetry: `OpenTelemetry.Extensions.Hosting`, `OpenTelemetry.Exporter.OpenTelemetryProtocol`
- Telemetry (local dev, non-Aspire): `OpenTelemetry.Exporter.Console` — register only in `Development` environment
- API versioning: `Asp.Versioning.Http`
- Health checks: `AspNetCore.HealthChecks.*` (community) for standard dependency checks
- Feature flags: `Microsoft.FeatureManagement.AspNetCore`
- Testing: `xunit.v3` + `NSubstitute`
- Integration testing: `Microsoft.AspNetCore.Mvc.Testing`, `Testcontainers`
- Snapshot testing: `Verify.Xunit`
- Benchmarking: `BenchmarkDotNet` (for performance-sensitive paths)

---

<!-- ═══════════════════════════════════════════════════ -->
<!-- 2. LANGUAGE & STYLE                                -->
<!-- ═══════════════════════════════════════════════════ -->

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

## Code Formatting
- Use `dotnet format` as the canonical formatter — do not use IDE-specific auto-format that may diverge.
- Run `dotnet format --verify-no-changes` in CI to gate PRs; never rely on developers remembering to format.
- The `.editorconfig` must enforce at minimum:
  - `indent_style`, `indent_size`, `end_of_line`, `charset`, `trim_trailing_whitespace`, `insert_final_newline`
  - `dotnet_sort_system_directives_first = true`
  - `dotnet_separate_import_directive_groups = false`
  - `csharp_style_namespace_declarations = file_scoped:error`
  - `csharp_style_var_for_built_in_types = false:suggestion` (explicit types for primitives)
  - `csharp_prefer_primary_constructors = true:suggestion`
  - Naming rules for `PascalCase` publics, `_camelCase` private fields, and `SCREAMING_SNAKE_CASE` constants
- Set diagnostic severities in `.editorconfig` (e.g., `dotnet_diagnostic.CA1062.severity = error`) — not in `<NoWarn>` properties that hide issues.
- Do not add `// dotnet format` suppression comments; fix the root cause or adjust the rule severity in `.editorconfig`.

## Code Complexity
- Maximum ~300 lines per class (hard limit: 1000). Extract collaborators when a class grows.
- Maximum cyclomatic complexity of 10 per method (hard limit: 20).
- Methods should have no more than 7 parameters; use a request/options object beyond that.
- Enforce separation of concerns: a class should have one reason to change (SRP).
- Avoid deep nesting (>3 levels); use early returns, guard clauses, or extract methods.

## Comments
- Comment **why**, not what.
- XML documentation on all public APIs only.
- No noise comments (e.g., `// Set x to 5`).

## Nullability & Defensive Coding
- Treat nullable warnings as errors (`<TreatWarningsAsErrors>true</TreatWarningsAsErrors>` or at least `<WarningsAsErrors>nullable</WarningsAsErrors>`).
- Use `ArgumentNullException.ThrowIfNull()` and `ArgumentException.ThrowIfNullOrWhiteSpace()` guard methods.
- Prefer pattern matching (`is null` / `is not null`) over `== null`.

---

<!-- ═══════════════════════════════════════════════════ -->
<!-- 3. ARCHITECTURE & DESIGN                           -->
<!-- ═══════════════════════════════════════════════════ -->

## Design
- Design public interfaces (with XML docs) before writing implementations.
- Follow SOLID and GRASP principles; prefer composition over inheritance.
- Use Dependency Injection via `Microsoft.Extensions.DependencyInjection`; never use the Service Locator pattern.
- Choose DI lifetimes deliberately: `Singleton` for stateless/thread-safe, `Scoped` for per-request, `Transient` for lightweight stateful.
  - Constructor injection is the default
  - Use factory patterns only when necessary

## Service Registration
- Group DI registrations in `IServiceCollection` extension methods per project/feature — e.g., `AddOrderingServices()`.
- Use keyed services (`[FromKeyedServices("name")]`) when multiple implementations of the same interface coexist.
- Guard against captive dependencies: never inject `Scoped` or `Transient` into `Singleton`.
- Call `builder.Services.ValidateOnBuild()` in `Development` to catch missing registrations at startup.

## API Design
- Use Minimal APIs for new endpoints; use controllers only when MVC conventions add clear value.
- Return `TypedResults` / `Results<T1, T2>` for compile-time OpenAPI metadata.
- Return `ProblemDetails` (RFC 9457) for all error responses — use `builder.Services.AddProblemDetails()`.
- Version APIs explicitly from day one via `Asp.Versioning.Http`.
- Accept `CancellationToken` in all endpoint signatures.
- Use `[AsParameters]` to group Minimal API parameters into a record.
- Prefer returning `IResult` over throwing exceptions for expected failures (400s, 404s, 409s).

## Configuration
- Bind configuration to strongly typed `IOptions<T>` / `IOptionsMonitor<T>` classes — never read raw `IConfiguration` values in business logic.
- Validate options at startup with `ValidateDataAnnotations()` or `ValidateOnStart()`.

## Feature Flags
- Use `Microsoft.FeatureManagement` for toggling features — never use `#if` compilation symbols for runtime flags.
- Gate new behavior behind feature flags for safe rollout; clean up flags after full rollout.

---

<!-- ═══════════════════════════════════════════════════ -->
<!-- 4. RUNTIME PATTERNS                                -->
<!-- ═══════════════════════════════════════════════════ -->

## Async/Await
- Never block with `.Result` or `.Wait()`; always `await`.
- Use `ConfigureAwait(false)` in library/non-UI code.
- Use `ValueTask<T>` for hot paths that usually complete synchronously.
- Always accept and propagate `CancellationToken`; default to `= default`.
- Never use `async void` except for event handlers.
- Handle cancellation tokens correctly.
- Use `IAsyncEnumerable<T>` for streaming responses.

## Long-Running & Background Tasks
- Use `BackgroundService` / `IHostedService` for long-running work — never fire-and-forget with `Task.Run`.
- Use Polly retry pipelines or the resilience pipeline for retry/restart on failure — not `ContinueWith`.
- For task chains, prefer `await` with `try/catch` over `ContinueWith` — it's safer and more readable.
- Register an `IHostApplicationLifetime` shutdown hook for graceful cleanup of background work.

## Concurrency & Thread Safety
- Use `Channel<T>` for producer/consumer patterns — not `BlockingCollection<T>`.
- Use `SemaphoreSlim` for async-compatible locking — never `lock` with `await` inside.
- Use `ConcurrentDictionary<K,V>` only when concurrent mutation is required; prefer `FrozenDictionary<K,V>` for read-heavy lookup data.
- Avoid `static` mutable state; if unavoidable, protect with appropriate synchronization.

## Error Handling
- Throw exceptions only for truly exceptional conditions.
- Include meaningful context in exception messages.
- Create custom exception types only when callers need to catch them specifically.
- Never swallow exceptions silently.
- Document thrown exceptions in XML `<exception>` tags.
- For expected domain failures (validation, not-found, conflict), use a Result/OneOf pattern instead of exceptions — exceptions are for unexpected failures only.

## Disposables & Resource Management
- Implement `IAsyncDisposable` for types holding unmanaged or async resources.
- Wrap unmanaged resources in `using` / `await using` — never rely on finalizers.
- Let the DI container manage disposal; don't manually dispose injected services.

---

<!-- ═══════════════════════════════════════════════════ -->
<!-- 5. DATA, SERIALIZATION & EXTERNAL I/O              -->
<!-- ═══════════════════════════════════════════════════ -->

## Serialization
- Use `System.Text.Json` source generators (`JsonSerializerContext`) for AOT-safe and faster serialization.
- Use `JsonStringEnumConverter` for enums — never serialize as integers in public APIs.
- Make DTOs immutable records with `[JsonPropertyName]` when wire names differ from C# conventions.

## Object Mapping
- Use Mapperly (source-generated) for object-to-object mapping — avoid reflection-based mappers like AutoMapper.
- Keep mapping logic in dedicated `*Mapper` static partial classes.
- Map at boundaries (API → domain, domain → persistence) — never pass DTOs deep into domain logic.

## Caching
- Use `HybridCache` (.NET 9+) as the default caching abstraction — it handles stampede protection and L1/L2 layering.
- Fall back to `IDistributedCache` only when `HybridCache` is not suitable.
- Never cache mutable objects; cache serialized/immutable representations.
- Set explicit expiration on every cache entry — never cache indefinitely.
- Use output caching middleware for HTTP response caching; do not hand-roll response caches.

## Resilience
- Use `Microsoft.Extensions.Http.Resilience` (Polly v8 pipeline) for all HTTP calls — configure retries, circuit breakers, and timeouts.
- Set explicit `HttpClient` timeouts; never rely on infinite defaults.
- Use `IHttpClientFactory` — never `new HttpClient()`.

## Health Checks
- Register `IHealthCheck` implementations for all critical dependencies (database, cache, external APIs).
- Expose `/health/ready` (readiness) and `/health/live` (liveness) endpoints separately.
- Health checks must be fast (<2s) and not trigger side effects.

---

<!-- ═══════════════════════════════════════════════════ -->
<!-- 6. PERFORMANCE & SOURCE GENERATION                 -->
<!-- ═══════════════════════════════════════════════════ -->

## Performance
- Prefer `Span<T>` / `ReadOnlySpan<T>` over array copies for short-lived data.
- Return `IReadOnlyCollection<T>` / `IReadOnlyList<T>` instead of `IEnumerable<T>` when count is needed.
- Use `StringBuilder` for 3+ string concatenations.
- Use `LoggerMessageAttribute` for structured, source-generated logging; never use string interpolation inside `ILogger` calls.
- Return empty collections, never `null`.

## Source Generators
- Prefer source-generated APIs over reflection: `System.Text.Json` generators, `LoggerMessage`, Mapperly, regex `GeneratedRegex`.
- When writing regex, use `[GeneratedRegex]` partial methods — never `new Regex()` at runtime.

---

<!-- ═══════════════════════════════════════════════════ -->
<!-- 7. OBSERVABILITY & DIAGNOSTICS                     -->
<!-- ═══════════════════════════════════════════════════ -->

## Logging
- Use `ILogger<T>` with `Microsoft.Extensions.Logging.Abstractions`.
- Define log messages via `[LoggerMessage]` partial methods — source-generated, zero-alloc.
- Log levels: `Trace` for verbose diagnostics, `Debug` for developer info, `Information` for business events, `Warning` for recoverable issues, `Error` for failures, `Critical` for app-threatening failures.
- Include correlation IDs and relevant entity IDs as structured properties — not embedded in message strings.
- Never log full request/response bodies in production; use `Debug`/`Trace` level behind a flag.

## Observability
- Use OpenTelemetry for all tracing, metrics, and structured logging — configure via `OpenTelemetry.Extensions.Hosting`.
- Emit traces (Activities) for all external calls: HTTP, database, message bus, cache.
- Emit metrics (counters, histograms) for request rates, latencies, and error rates on public-facing endpoints.
- Use `ActivitySource` for custom spans; name sources after the assembly.
- Propagate distributed trace context (`traceparent` / `baggage`) across service boundaries.
- Correlate logs with traces via `ILogger` + OpenTelemetry log exporter — never build a separate correlation mechanism.
- In local development, register `OpenTelemetry.Exporter.Console` (or use the Aspire dashboard) to verify traces, metrics, and logs are emitted correctly — never ship console exporters to production.

## Debugging & Diagnostics
- Apply `[DebuggerDisplay]` to DTOs, value objects, and entity types for readable debugger output.
- Use `[DebuggerStepThrough]` on trivial pass-through or generated code.
- Use `ToString()` overrides on key domain types for logging clarity.

---

<!-- ═══════════════════════════════════════════════════ -->
<!-- 8. SECURITY                                        -->
<!-- ═══════════════════════════════════════════════════ -->

## Security
- Validate all external input at system boundaries; use FluentValidation or Data Annotations.
- Never log secrets, tokens, or PII — use `[LogProperties(SkipNullProperties = true)]` and redaction where needed.
- Use parameterized queries or EF Core — never concatenate user input into SQL/commands.
- Store secrets in Azure Key Vault or User Secrets; never in source or appsettings.json.
- Use `TimeProvider` (abstracted clock) instead of `DateTime.Now`/`DateTimeOffset.Now` for testability.

---

<!-- ═══════════════════════════════════════════════════ -->
<!-- 9. TESTING                                         -->
<!-- ═══════════════════════════════════════════════════ -->

## Testing
- Write tests against the public interface, not the implementation.
- Use Arrange / Act / Assert structure.
- Name tests: `MethodName_Scenario_ExpectedResult` or `Should_Behavior_When_Condition`.
- Use `[Theory]` + `[InlineData]` for parameterized edge cases.
- Mock interfaces, not concrete classes.
- Use `WebApplicationFactory<T>` for integration tests; override services with test doubles in `ConfigureTestServices`.
- Use Testcontainers for database integration tests — no shared/static database state.
- Use `Verify` for snapshot testing of serialization, API responses, or complex output.
- Never use `Thread.Sleep` in tests; use `TaskCompletionSource`, polling helpers, or `ManualResetEventSlim`.
- Test projects mirror the source project structure: `MyProject` → `MyProject.Tests`.

---

<!-- ═══════════════════════════════════════════════════ -->
<!-- 10. DEPLOYMENT                                     -->
<!-- ═══════════════════════════════════════════════════ -->

## Containers
- Use the .NET SDK publish container (`dotnet publish /t:PublishContainer`) or multi-stage Dockerfiles.
- Base on `mcr.microsoft.com/dotnet/runtime` or `aspnet` — never the SDK image for production.
- Run as non-root (`USER app`) and set `DOTNET_EnableDiagnostics=0` in production containers.
- Use `.dockerignore` mirroring `.gitignore` patterns to minimize context size.