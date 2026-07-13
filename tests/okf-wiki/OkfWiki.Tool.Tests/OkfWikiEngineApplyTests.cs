using System.Text.Json;
using OkfWiki.Tool;

namespace OkfWiki.Tool.Tests;

public sealed class OkfWikiEngineApplyTests
{
    private static readonly DateTimeOffset FixedTime =
        new(2026, 7, 11, 7, 25, 10, TimeSpan.Zero);

    [Fact]
    public void Apply_CreateConcept_WritesConformantBundle()
    {
        using TemporaryDirectory temporaryDirectory = new();
        string bundle = System.IO.Path.Combine(temporaryDirectory.Path, "llm-wiki");
        OkfWikiEngine engine = CreateEngine();

        ApplyResult result = engine.Apply(
            bundle,
            CreateManifest(
                "create",
                "tables/orders",
                metadata: JsonSerializer.SerializeToElement(
                    new { owner = new { team = "data" } })));

        Assert.Equal("applied", result.Status);
        Assert.Equal("tables/orders", result.ConceptId);
        Assert.Equal(5, result.Changes.Count);
        Assert.Empty(result.Warnings);
        string concept = File.ReadAllText(
            System.IO.Path.Combine(bundle, "tables", "orders.md"));
        Assert.Contains("type: Table", concept);
        Assert.Contains("owner:", concept);
        Assert.Contains("team: data", concept);
        Assert.Contains("timestamp: 2026-07-11T07:25:10Z", concept);
        Assert.Contains("# Schema", concept);
        Assert.Contains(
            "* [Orders](orders.md) - One row per order.",
            File.ReadAllText(System.IO.Path.Combine(bundle, "tables", "index.md")));
        Assert.Contains(
            "* [Tables](tables/) - Knowledge concepts under tables.",
            File.ReadAllText(System.IO.Path.Combine(bundle, "index.md")));
        Assert.True(engine.Validate(bundle).IsValid);
    }

    [Fact]
    public void Apply_UpdateByPath_PreservesUnknownMetadata()
    {
        using TemporaryDirectory temporaryDirectory = new();
        string bundle = temporaryDirectory.Path;
        string conceptPath = System.IO.Path.Combine(bundle, "orders.md");
        File.WriteAllText(
            conceptPath,
            """
            ---
            type: Table
            title: Old Orders
            resource: urn:orders
            owner:
              team: data
              tier: 1
            timestamp: 2026-01-01T00:00:00Z
            ---

            Old body.
            """);
        OkfWikiEngine engine = CreateEngine();

        ApplyResult result = engine.Apply(
            bundle,
            CreateManifest(
                "update",
                "orders.md",
                title: "Orders",
                body: "New body."));

        Assert.Equal("applied", result.Status);
        string concept = File.ReadAllText(conceptPath);
        Assert.Contains("title: Orders", concept);
        Assert.Contains("owner:", concept);
        Assert.Contains("team: data", concept);
        Assert.Contains("tier: 1", concept);
        Assert.Contains("New body.", concept);
        Assert.DoesNotContain("Old body.", concept);
    }

    [Fact]
    public void Apply_UpdateByResource_UsesUniqueMatch()
    {
        using TemporaryDirectory temporaryDirectory = new();
        string bundle = temporaryDirectory.Path;
        WriteConcept(bundle, "one.md", "urn:one", "One");
        OkfWikiEngine engine = CreateEngine();

        ApplyResult result = engine.Apply(
            bundle,
            CreateManifest(
                "update",
                conceptPath: null,
                matchResource: "urn:one",
                title: "Updated One"));

        Assert.Equal("one", result.ConceptId);
        Assert.Contains(
            "title: Updated One",
            File.ReadAllText(System.IO.Path.Combine(bundle, "one.md")));
    }

    [Fact]
    public void Apply_UpdateByResource_RejectsAmbiguousMatch()
    {
        using TemporaryDirectory temporaryDirectory = new();
        WriteConcept(temporaryDirectory.Path, "one.md", "urn:duplicate", "One");
        WriteConcept(temporaryDirectory.Path, "two.md", "urn:duplicate", "Two");
        OkfWikiEngine engine = CreateEngine();

        OkfWikiException exception = Assert.Throws<OkfWikiException>(
            () => engine.Apply(
                temporaryDirectory.Path,
                CreateManifest(
                    "update",
                    conceptPath: null,
                    matchResource: "urn:duplicate",
                    title: "Updated")));

        Assert.Contains("matches multiple concepts", exception.Message);
    }

    [Fact]
    public void Apply_UpdateWithoutIdentity_RejectsOperation()
    {
        using TemporaryDirectory temporaryDirectory = new();
        OkfWikiEngine engine = CreateEngine();

        OkfWikiException exception = Assert.Throws<OkfWikiException>(
            () => engine.Apply(
                temporaryDirectory.Path,
                CreateManifest("update", conceptPath: null)));

        Assert.Contains("conceptPath or matchResource", exception.Message);
    }

    [Theory]
    [InlineData("..\\outside")]
    [InlineData(".md")]
    [InlineData("nested/.md")]
    [InlineData("index.md")]
    [InlineData("nested/log.md")]
    public void Apply_UnsafeOrReservedPath_RejectsOperation(string conceptPath)
    {
        using TemporaryDirectory temporaryDirectory = new();
        OkfWikiEngine engine = CreateEngine();

        Assert.Throws<OkfWikiException>(
            () => engine.Apply(
                temporaryDirectory.Path,
                CreateManifest("create", conceptPath)));
    }

    [Fact]
    public void Apply_DryRun_ReportsChangesWithoutWriting()
    {
        using TemporaryDirectory temporaryDirectory = new();
        string bundle = System.IO.Path.Combine(temporaryDirectory.Path, "preview");
        OkfWikiEngine engine = CreateEngine();

        ApplyResult result = engine.Apply(
            bundle,
            CreateManifest("create", "concepts/example"),
            dryRun: true);

        Assert.Equal("preview", result.Status);
        Assert.True(result.DryRun);
        Assert.False(Directory.Exists(bundle));
        Assert.Contains(result.Changes, change => change.Path == "concepts/example.md");
    }

    [Fact]
    public void Apply_UnchangedUpdate_DoesNotRewriteGeneratedFiles()
    {
        using TemporaryDirectory temporaryDirectory = new();
        OkfWikiEngine engine = CreateEngine();
        engine.Apply(
            temporaryDirectory.Path,
            CreateManifest("create", "orders"));
        string logPath = System.IO.Path.Combine(temporaryDirectory.Path, "log.md");
        string originalLog = File.ReadAllText(logPath);

        ApplyResult result = engine.Apply(
            temporaryDirectory.Path,
            new OperationManifest
            {
                Action = "update",
                ConceptPath = "orders"
            });

        Assert.Equal("unchanged", result.Status);
        Assert.Empty(result.Changes);
        Assert.Equal(originalLog, File.ReadAllText(logPath));
    }

    [Fact]
    public void Apply_RootConcept_WritesOneLogEntry()
    {
        using TemporaryDirectory temporaryDirectory = new();
        OkfWikiEngine engine = CreateEngine();

        ApplyResult result = engine.Apply(
            temporaryDirectory.Path,
            CreateManifest("create", "overview"));

        Assert.Single(result.Changes, change => change.Kind == "log");
        string log = File.ReadAllText(
            System.IO.Path.Combine(temporaryDirectory.Path, "log.md"));
        Assert.Equal(1, CountOccurrences(log, "**Creation**"));
    }

    [Fact]
    public void Apply_ExistingRootVersion_PreservesVersion()
    {
        using TemporaryDirectory temporaryDirectory = new();
        File.WriteAllText(
            System.IO.Path.Combine(temporaryDirectory.Path, "index.md"),
            """
            ---
            okf_version: "0.2"
            ---

            # Concepts

            * [Old](old.md)
            """);
        OkfWikiEngine engine = CreateEngine();

        engine.Apply(
            temporaryDirectory.Path,
            CreateManifest("create", "new"));

        Assert.Contains(
            "okf_version: \"0.2\"",
            File.ReadAllText(
                System.IO.Path.Combine(temporaryDirectory.Path, "index.md")));
    }

    [Fact]
    public void Apply_RemoveFields_RemovesOptionalMetadata()
    {
        using TemporaryDirectory temporaryDirectory = new();
        OkfWikiEngine engine = CreateEngine();
        engine.Apply(
            temporaryDirectory.Path,
            CreateManifest("create", "orders"));

        engine.Apply(
            temporaryDirectory.Path,
            new OperationManifest
            {
                Action = "update",
                ConceptPath = "orders",
                RemoveFields = ["description"]
            });

        string concept = File.ReadAllText(
            System.IO.Path.Combine(temporaryDirectory.Path, "orders.md"));
        Assert.DoesNotContain("description:", concept);
    }

    [Fact]
    public void Apply_NewerLogDate_IsInsertedFirst()
    {
        using TemporaryDirectory temporaryDirectory = new();
        CreateEngine().Apply(
            temporaryDirectory.Path,
            CreateManifest("create", "orders"));
        OkfWikiEngine nextDayEngine = new(
            new TestTimeProvider(FixedTime.AddDays(1)));

        nextDayEngine.Apply(
            temporaryDirectory.Path,
            new OperationManifest
            {
                Action = "update",
                ConceptPath = "orders",
                Title = "Orders Updated"
            });
        OkfWikiEngine previousDayEngine = new(
            new TestTimeProvider(FixedTime.AddDays(-1)));
        previousDayEngine.Apply(
            temporaryDirectory.Path,
            new OperationManifest
            {
                Action = "update",
                ConceptPath = "orders",
                Title = "Orders Updated Again"
            });

        string log = File.ReadAllText(
            System.IO.Path.Combine(temporaryDirectory.Path, "log.md"));
        Assert.True(
            log.IndexOf("## 2026-07-12", StringComparison.Ordinal) <
            log.IndexOf("## 2026-07-11", StringComparison.Ordinal));
        Assert.True(
            log.IndexOf("## 2026-07-11", StringComparison.Ordinal) <
            log.IndexOf("## 2026-07-10", StringComparison.Ordinal));
    }

    [Fact]
    public void Apply_MultilineDescription_RejectsOperation()
    {
        using TemporaryDirectory temporaryDirectory = new();
        OkfWikiEngine engine = CreateEngine();
        OperationManifest manifest = CreateManifest("create", "orders") with
        {
            Description = "Line one.\nLine two."
        };

        OkfWikiException exception = Assert.Throws<OkfWikiException>(
            () => engine.Apply(temporaryDirectory.Path, manifest));

        Assert.Contains("description must be a single-line", exception.Message);
    }

    [Fact]
    public void Apply_BlankTitle_RejectsOperation()
    {
        using TemporaryDirectory temporaryDirectory = new();
        OperationManifest manifest = CreateManifest("create", "orders") with
        {
            Title = " "
        };

        OkfWikiException exception = Assert.Throws<OkfWikiException>(
            () => CreateEngine().Apply(temporaryDirectory.Path, manifest));

        Assert.Contains("title cannot be empty", exception.Message);
        Assert.False(File.Exists(
            System.IO.Path.Combine(temporaryDirectory.Path, "orders.md")));
    }

    [Fact]
    public void Apply_NullAction_ReturnsDomainError()
    {
        using TemporaryDirectory temporaryDirectory = new();
        OperationManifest manifest = CreateManifest("create", "orders") with
        {
            Action = null!
        };

        OkfWikiException exception = Assert.Throws<OkfWikiException>(
            () => CreateEngine().Apply(temporaryDirectory.Path, manifest));

        Assert.Equal("action is required.", exception.Message);
    }

    [Fact]
    public void Apply_TimestampWithoutOffset_RejectsOperation()
    {
        using TemporaryDirectory temporaryDirectory = new();
        OperationManifest manifest = CreateManifest("create", "orders") with
        {
            Timestamp = "2026-07-11T00:00:00"
        };

        OkfWikiException exception = Assert.Throws<OkfWikiException>(
            () => CreateEngine().Apply(temporaryDirectory.Path, manifest));

        Assert.Contains("with Z or an explicit offset", exception.Message);
    }

    [Fact]
    public void Apply_TimestampWithOffset_NormalizesToUtc()
    {
        using TemporaryDirectory temporaryDirectory = new();
        OperationManifest manifest = CreateManifest("create", "orders") with
        {
            Timestamp = "2026-07-11T02:00:00+02:00"
        };

        CreateEngine().Apply(temporaryDirectory.Path, manifest);

        Assert.Contains(
            "timestamp: 2026-07-11T00:00:00Z",
            File.ReadAllText(
                System.IO.Path.Combine(temporaryDirectory.Path, "orders.md")));
    }

    [Fact]
    public void Apply_WriteFailure_RollsBackEveryPlannedFile()
    {
        using TemporaryDirectory temporaryDirectory = new();
        string rootLogDirectory = System.IO.Path.Combine(
            temporaryDirectory.Path,
            "log.md");
        Directory.CreateDirectory(rootLogDirectory);
        OkfWikiEngine engine = CreateEngine();

        Assert.Throws<IOException>(
            () => engine.Apply(
                temporaryDirectory.Path,
                CreateManifest("create", "tables/orders")));

        Assert.True(Directory.Exists(rootLogDirectory));
        Assert.False(File.Exists(
            System.IO.Path.Combine(temporaryDirectory.Path, "index.md")));
        Assert.False(Directory.Exists(
            System.IO.Path.Combine(temporaryDirectory.Path, "tables")));
        Assert.Empty(
            Directory.EnumerateFiles(
                temporaryDirectory.Path,
                "*.stage",
                SearchOption.AllDirectories));
        Assert.Empty(
            Directory.EnumerateFiles(
                temporaryDirectory.Path,
                "*.backup",
                SearchOption.AllDirectories));
    }

    [Fact]
    public void Apply_ConceptBelowDirectoryLink_RejectsOperation()
    {
        using TemporaryDirectory temporaryDirectory = new();
        string bundle = System.IO.Path.Combine(temporaryDirectory.Path, "bundle");
        string outside = System.IO.Path.Combine(temporaryDirectory.Path, "outside");
        Directory.CreateDirectory(bundle);
        Directory.CreateDirectory(outside);
        string link = System.IO.Path.Combine(bundle, "linked");
        try
        {
            Directory.CreateSymbolicLink(link, outside);
        }
        catch (UnauthorizedAccessException)
        {
            Assert.Skip("The test environment cannot create directory symlinks.");
        }
        catch (PlatformNotSupportedException)
        {
            Assert.Skip("The test platform does not support directory symlinks.");
        }

        OkfWikiException exception = Assert.Throws<OkfWikiException>(
            () => CreateEngine().Apply(
                bundle,
                CreateManifest("create", "linked/orders")));

        Assert.Contains("symbolic link or reparse point", exception.Message);
        Assert.False(File.Exists(System.IO.Path.Combine(outside, "orders.md")));
    }

    private static OkfWikiEngine CreateEngine()
    {
        return new OkfWikiEngine(new TestTimeProvider(FixedTime));
    }

    private static OperationManifest CreateManifest(
        string action,
        string? conceptPath,
        string? matchResource = null,
        string? title = "Orders",
        string? body = "# Schema\n\nOrder data.",
        JsonElement metadata = default)
    {
        return new OperationManifest
        {
            Action = action,
            ConceptPath = conceptPath,
            MatchResource = matchResource,
            Type = action == "create" ? "Table" : null,
            Title = title,
            Description = action == "create" ? "One row per order." : null,
            Resource = action == "create" ? "urn:orders" : null,
            Tags = action == "create" ? ["sales", "orders"] : null,
            Metadata = metadata,
            Body = body,
            LogMessage = "Changed the orders concept."
        };
    }

    private static void WriteConcept(
        string bundle,
        string relativePath,
        string resource,
        string title)
    {
        string path = System.IO.Path.Combine(bundle, relativePath);
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path)!);
        File.WriteAllText(
            path,
            $"""
            ---
            type: Reference
            title: {title}
            resource: {resource}
            ---

            Body.
            """);
    }

    private static int CountOccurrences(string value, string search)
    {
        return value.Split(search, StringSplitOptions.None).Length - 1;
    }
}
