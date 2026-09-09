[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$installScript = Join-Path $repositoryRoot "install-skills.ps1"
$uninstallScript = Join-Path $repositoryRoot "uninstall-skills.ps1"
$temporaryProfile = Join-Path (
    [IO.Path]::GetTempPath()
) "okf-wiki-install-tests-$([Guid]::NewGuid().ToString('N'))"
$skillsDirectory = Join-Path $temporaryProfile ".copilot\skills"
$installedSkill = Join-Path $skillsDirectory "okf-wiki"
$unrelatedSkill = Join-Path $skillsDirectory "user-owned-skill"
$originalUserProfile = $env:USERPROFILE

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
}

try {
    New-Item -ItemType Directory -Path $temporaryProfile -Force | Out-Null
    $env:USERPROFILE = $temporaryProfile

    & $installScript -Runtime copilot -Force | Out-Null

    Assert-True (
        Test-Path -LiteralPath (Join-Path $installedSkill "SKILL.md")
    ) "The OKF skill definition should be installed"
    Assert-True (
        Test-Path -LiteralPath (
            Join-Path $installedSkill "tool\OkfWiki.Tool\OkfWiki.Tool.csproj"
        )
    ) "The nested .NET tool project should be installed"
    Assert-True (
        Test-Path -LiteralPath (
            Join-Path $installedSkill "tool\Directory.Packages.props"
        )
    ) "The tool's pinned package configuration should be installed"
    Assert-True (
        Test-Path -LiteralPath (
            Join-Path $installedSkill "tool\Directory.Build.props"
        )
    ) "The tool's .NET 10 build configuration should be installed"
    Assert-True (
        Test-Path -LiteralPath (
            Join-Path $installedSkill "tool\OkfWiki.Tool\OkfWikiEngine.cs"
        )
    ) "The nested .NET tool sources should be installed"
    Assert-True (
        -not (Test-Path -LiteralPath (
            Join-Path $installedSkill "tool\OkfWiki.Tool\bin"
        ))
    ) "Generated bin output should not be installed"
    Assert-True (
        -not (Test-Path -LiteralPath (
            Join-Path $installedSkill "tool\OkfWiki.Tool\obj"
        ))
    ) "Generated obj output should not be installed"

    $validationBundle = Join-Path $temporaryProfile "validation-bundle"
    New-Item -ItemType Directory -Path $validationBundle -Force | Out-Null
    @"
---
type: Reference
---

Installed tool smoke test.
"@ | Set-Content -LiteralPath (Join-Path $validationBundle "concept.md")
    $toolProject = Join-Path (
        $installedSkill
    ) "tool\OkfWiki.Tool\OkfWiki.Tool.csproj"
    & dotnet build $toolProject --nologo --verbosity quiet | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "The installed .NET tool should build"
    $validationJson = & dotnet run --project $toolProject --no-build -- `
        validate --bundle $validationBundle --json
    Assert-True ($LASTEXITCODE -eq 0) "The installed .NET tool should run"
    $validation = $validationJson | ConvertFrom-Json
    Assert-True $validation.isValid "The installed tool should validate a conformant bundle"

    $stalePath = Join-Path $installedSkill "stale-file.txt"
    Set-Content -LiteralPath $stalePath -Value "stale"
    & $installScript -Runtime copilot -Force | Out-Null
    Assert-True (
        -not (Test-Path -LiteralPath $stalePath)
    ) "Forced reinstallation should replace the complete skill directory"

    New-Item -ItemType Directory -Path $unrelatedSkill -Force | Out-Null
    Set-Content -LiteralPath (
        Join-Path $unrelatedSkill "SKILL.md"
    ) -Value "# User-owned skill"

    & $uninstallScript -Runtime copilot -Force | Out-Null

    Assert-True (
        -not (Test-Path -LiteralPath $installedSkill)
    ) "The OKF skill directory should be removed"
    Assert-True (
        Test-Path -LiteralPath (Join-Path $unrelatedSkill "SKILL.md")
    ) "Uninstallation should preserve unrelated user skills"

    "All OKF skill installation tests passed."
} finally {
    $env:USERPROFILE = $originalUserProfile
    if (Test-Path -LiteralPath $temporaryProfile) {
        Remove-Item -LiteralPath $temporaryProfile -Recurse -Force
    }
}
