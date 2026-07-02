<#
.SYNOPSIS
    Installs commandline-crew skills to user's Copilot CLI configuration.

.DESCRIPTION
    Copies each skill folder from this repository's skills\ directory to
    C:\Users\<USER>\.copilot\skills\<skill-name>\. Skills are picked up
    automatically by the Copilot CLI on the next session.

.PARAMETER Force
    Overwrites existing skill folders without prompting.

.EXAMPLE
    .\install-skills.ps1
    .\install-skills.ps1 -Force
#>

param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Paths
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceSkillsDir = Join-Path $scriptDir "skills"
$targetCopilotDir = Join-Path $env:USERPROFILE ".copilot"
$targetSkillsDir = Join-Path $targetCopilotDir "skills"

Write-Host "Commandline Crew - Skills Installer" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""

# Check source exists
if (-not (Test-Path $sourceSkillsDir)) {
    Write-Host "ERROR: Source skills directory not found: $sourceSkillsDir" -ForegroundColor Red
    exit 1
}

$sourceSkills = Get-ChildItem -Path $sourceSkillsDir -Directory -ErrorAction SilentlyContinue

if (-not $sourceSkills -or $sourceSkills.Count -eq 0) {
    Write-Host "WARNING: No skills found in $sourceSkillsDir" -ForegroundColor Yellow
    exit 0
}

# Create .copilot / skills directories if needed
if (-not (Test-Path $targetCopilotDir)) {
    Write-Host "Creating .copilot directory: $targetCopilotDir" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $targetCopilotDir -Force | Out-Null
}
if (-not (Test-Path $targetSkillsDir)) {
    Write-Host "Creating skills directory: $targetSkillsDir" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $targetSkillsDir -Force | Out-Null
}

Write-Host "Found $($sourceSkills.Count) skill(s) to install:" -ForegroundColor Green
$sourceSkills | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
Write-Host ""

$installed = 0
$skipped = 0

foreach ($skill in $sourceSkills) {
    $sourceSkillMd = Join-Path $skill.FullName "SKILL.md"
    if (-not (Test-Path $sourceSkillMd)) {
        Write-Host "  Skipped: $($skill.Name) (missing SKILL.md)" -ForegroundColor Yellow
        $skipped++
        continue
    }

    $targetPath = Join-Path $targetSkillsDir $skill.Name
    if (Test-Path $targetPath) {
        if (-not $Force) {
            $response = Read-Host "Skill '$($skill.Name)' already exists. Overwrite? [y/N]"
            if ($response -notmatch "^[Yy]") {
                Write-Host "  Skipped: $($skill.Name)" -ForegroundColor Yellow
                $skipped++
                continue
            }
        }
        Remove-Item -Path $targetPath -Recurse -Force
    }

    Copy-Item -Path $skill.FullName -Destination $targetPath -Recurse -Force
    Write-Host "  Installed: $($skill.Name)" -ForegroundColor Green
    $installed++
}

Write-Host ""
Write-Host "Installation complete!" -ForegroundColor Cyan
Write-Host "  Installed: $installed skill(s)" -ForegroundColor Green
if ($skipped -gt 0) {
    Write-Host "  Skipped:   $skipped skill(s)" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "Skills are now available. Copilot CLI will pick them up on the next session." -ForegroundColor Gray
