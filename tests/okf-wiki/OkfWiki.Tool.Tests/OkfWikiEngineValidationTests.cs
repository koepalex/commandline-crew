using System.Text;
using OkfWiki.Tool;

namespace OkfWiki.Tool.Tests;

public sealed class OkfWikiEngineValidationTests
{
    [Fact]
    public void Validate_MalformedYaml_ReportsError()
    {
        using TemporaryDirectory temporaryDirectory = new();
        File.WriteAllText(
            System.IO.Path.Combine(temporaryDirectory.Path, "bad.md"),
            "---\ntype: [invalid\n---\n");

        ValidationResult result = new OkfWikiEngine().Validate(temporaryDirectory.Path);

        Assert.False(result.IsValid);
        Assert.Contains(
            result.Diagnostics,
            diagnostic => diagnostic.Code == "concept.frontmatter.invalid");
    }

    [Fact]
    public void Validate_UnclosedFlowSequenceWithFollowingField_ReportsError()
    {
        using TemporaryDirectory temporaryDirectory = new();
        File.WriteAllText(
            System.IO.Path.Combine(temporaryDirectory.Path, "bad.md"),
            """
            ---
            type: [broken
            title: Bad YAML
            ---
            # Body
            """);

        ValidationResult result = new OkfWikiEngine().Validate(temporaryDirectory.Path);

        Assert.False(result.IsValid);
        Assert.Contains(
            result.Diagnostics,
            diagnostic => diagnostic.Code == "concept.frontmatter.invalid");
    }

    [Fact]
    public void Validate_MissingType_ReportsError()
    {
        using TemporaryDirectory temporaryDirectory = new();
        File.WriteAllText(
            System.IO.Path.Combine(temporaryDirectory.Path, "bad.md"),
            "---\ntitle: Missing Type\n---\n");

        ValidationResult result = new OkfWikiEngine().Validate(temporaryDirectory.Path);

        Assert.False(result.IsValid);
        Assert.Contains(
            result.Diagnostics,
            diagnostic => diagnostic.Code == "concept.type.required");
    }

    [Fact]
    public void Validate_MalformedIndexAndLog_ReportErrors()
    {
        using TemporaryDirectory temporaryDirectory = new();
        File.WriteAllText(
            System.IO.Path.Combine(temporaryDirectory.Path, "index.md"),
            "# Concepts\n\nThis is not an entry.\n");
        File.WriteAllText(
            System.IO.Path.Combine(temporaryDirectory.Path, "log.md"),
            "# Log\n\n## July 11\nNot a list item.\n");

        ValidationResult result = new OkfWikiEngine().Validate(temporaryDirectory.Path);

        Assert.False(result.IsValid);
        Assert.Contains(
            result.Diagnostics,
            diagnostic => diagnostic.Code == "index.structure.invalid");
        Assert.Contains(
            result.Diagnostics,
            diagnostic => diagnostic.Code == "log.structure.invalid");
    }

    [Fact]
    public void Validate_DuplicateResources_ReportEachConcept()
    {
        using TemporaryDirectory temporaryDirectory = new();
        WriteConcept(temporaryDirectory.Path, "one.md", "urn:duplicate");
        WriteConcept(temporaryDirectory.Path, "two.md", "urn:duplicate");

        ValidationResult result = new OkfWikiEngine().Validate(temporaryDirectory.Path);

        Assert.True(result.IsValid);
        Assert.Equal(
            2,
            result.Diagnostics.Count(
                diagnostic => diagnostic.Code == "concept.resource.duplicate" &&
                    diagnostic.Severity == "warning"));
    }

    [Fact]
    public void Validate_UnknownTypeFieldsAndBrokenLink_AreTolerated()
    {
        using TemporaryDirectory temporaryDirectory = new();
        File.WriteAllText(
            System.IO.Path.Combine(temporaryDirectory.Path, "custom.md"),
            """
            ---
            type: Organization-Specific Artifact
            custom:
              score: 42
            ---

            See [future knowledge](/missing.md).
            """);

        ValidationResult result = new OkfWikiEngine().Validate(temporaryDirectory.Path);

        Assert.True(result.IsValid);
        Assert.Equal(1, result.ConceptCount);
        Assert.Empty(result.Diagnostics);
    }

    [Fact]
    public void Validate_NonRootIndexFrontmatter_ReportsError()
    {
        using TemporaryDirectory temporaryDirectory = new();
        string nested = System.IO.Path.Combine(temporaryDirectory.Path, "nested");
        Directory.CreateDirectory(nested);
        File.WriteAllText(
            System.IO.Path.Combine(nested, "index.md"),
            "---\nokf_version: \"0.1\"\n---\n\n# Concepts\n");

        ValidationResult result = new OkfWikiEngine().Validate(temporaryDirectory.Path);

        Assert.False(result.IsValid);
        Assert.Contains(
            result.Diagnostics,
            diagnostic => diagnostic.Code == "index.frontmatter.forbidden");
    }

    [Fact]
    public void Validate_Utf16Concept_ReportsEncodingError()
    {
        using TemporaryDirectory temporaryDirectory = new();
        File.WriteAllText(
            System.IO.Path.Combine(temporaryDirectory.Path, "utf16.md"),
            "---\ntype: Reference\n---\n",
            Encoding.Unicode);

        ValidationResult result = new OkfWikiEngine().Validate(temporaryDirectory.Path);

        Assert.False(result.IsValid);
        Assert.Contains(
            result.Diagnostics,
            diagnostic => diagnostic.Code == "file.encoding.invalid");
    }

    [Fact]
    public void Validate_Utf8BomConcept_ReportsEncodingError()
    {
        using TemporaryDirectory temporaryDirectory = new();
        File.WriteAllText(
            System.IO.Path.Combine(temporaryDirectory.Path, "bom.md"),
            "---\ntype: Reference\n---\n",
            new UTF8Encoding(encoderShouldEmitUTF8Identifier: true));

        ValidationResult result = new OkfWikiEngine().Validate(temporaryDirectory.Path);

        Assert.False(result.IsValid);
        Assert.Contains(
            result.Diagnostics,
            diagnostic => diagnostic.Code == "file.encoding.invalid");
    }

    [Fact]
    public void Validate_ImpossibleLogDate_ReportsError()
    {
        using TemporaryDirectory temporaryDirectory = new();
        File.WriteAllText(
            System.IO.Path.Combine(temporaryDirectory.Path, "log.md"),
            "# Directory Update Log\n\n## 2026-99-99\n* Entry\n");

        ValidationResult result = new OkfWikiEngine().Validate(temporaryDirectory.Path);

        Assert.False(result.IsValid);
        Assert.Contains(
            result.Diagnostics,
            diagnostic => diagnostic.Code == "log.date.invalid");
    }

    private static void WriteConcept(
        string bundle,
        string relativePath,
        string resource)
    {
        File.WriteAllText(
            System.IO.Path.Combine(bundle, relativePath),
            $"""
            ---
            type: Reference
            resource: {resource}
            ---

            Body.
            """);
    }
}
