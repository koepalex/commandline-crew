<#
.SYNOPSIS
    Uninstalls commandline-crew skills from user's Copilot CLI configuration.

.DESCRIPTION
    Removes each skill folder that was installed by install-skills.ps1 from
    C:\Users\<USER>\.copilot\skills\<skill-name>\. Only skills that exist in
    this repository's skills\ directory are removed; other user-installed
    skills are preserved.

.PARAMETER Force
    Removes skill folders without prompting for confirmation.

.EXAMPLE
    .\uninstall-skills.ps1
    .\uninstall-skills.ps1 -Force
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

Write-Host "Commandline Crew - Skills Uninstaller" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $targetSkillsDir)) {
    Write-Host "No skills directory found at: $targetSkillsDir" -ForegroundColor Yellow
    Write-Host "Nothing to uninstall." -ForegroundColor Gray
    exit 0
}

if (-not (Test-Path $sourceSkillsDir)) {
    Write-Host "WARNING: Cannot determine which skills to remove (source not found)." -ForegroundColor Yellow
    exit 1
}

$sourceSkills = Get-ChildItem -Path $sourceSkillsDir -Directory -ErrorAction SilentlyContinue
if (-not $sourceSkills -or $sourceSkills.Count -eq 0) {
    Write-Host "No skills defined in this repository. Nothing to uninstall." -ForegroundColor Yellow
    exit 0
}

# Find installed skills that came from this repo
$skillsToRemove = @()
foreach ($skill in $sourceSkills) {
    $targetPath = Join-Path $targetSkillsDir $skill.Name
    if (Test-Path $targetPath) {
        $skillsToRemove += [PSCustomObject]@{
            Name = $skill.Name
            Path = $targetPath
        }
    }
}

if ($skillsToRemove.Count -eq 0) {
    Write-Host "No commandline-crew skills found to uninstall." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($skillsToRemove.Count) skill(s) to uninstall:" -ForegroundColor Yellow
$skillsToRemove | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
Write-Host ""

if (-not $Force) {
    $response = Read-Host "Are you sure you want to remove these skills? [y/N]"
    if ($response -notmatch "^[Yy]") {
        Write-Host "Uninstall cancelled." -ForegroundColor Yellow
        exit 0
    }
}

$removed = 0
foreach ($skill in $skillsToRemove) {
    Remove-Item -Path $skill.Path -Recurse -Force
    Write-Host "  Removed: $($skill.Name)" -ForegroundColor Green
    $removed++
}

Write-Host ""
Write-Host "Uninstall complete!" -ForegroundColor Cyan
Write-Host "  Removed: $removed skill(s)" -ForegroundColor Green

# Offer to remove the skills directory if it is now empty
$remaining = Get-ChildItem -Path $targetSkillsDir -ErrorAction SilentlyContinue
if (-not $remaining -or $remaining.Count -eq 0) {
    if ($Force) {
        Remove-Item -Path $targetSkillsDir -Force
        Write-Host "  Removed empty skills directory" -ForegroundColor Gray
    } else {
        $response = Read-Host "Skills directory is now empty. Remove it? [y/N]"
        if ($response -match "^[Yy]") {
            Remove-Item -Path $targetSkillsDir -Force
            Write-Host "  Removed empty skills directory" -ForegroundColor Gray
        }
    }
}
