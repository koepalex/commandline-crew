<#
.SYNOPSIS
    Installs commandline-crew skills to user's Copilot CLI configuration.

.DESCRIPTION
    Copies each skill folder from this repository's skills\ directory to
    C:\Users\<USER>\.copilot\skills\<skill-name>\. Skills are picked up
    automatically by the Copilot CLI on the next session.

.PARAMETER Force
    Overwrites existing skill folders without prompting. If Skill is omitted,
    installs all available skills.

.PARAMETER Skill
    Installs only the named skills. Accepts one or more skill folder names.
    If omitted, the installer displays an interactive selection list.

.EXAMPLE
    .\install-skills.ps1
    .\install-skills.ps1 -Skill ask-folder,workflow-goal
    .\install-skills.ps1 -Force
#>

param(
    [string[]]$Skill,
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

$sourceSkills = @(
    Get-ChildItem -Path $sourceSkillsDir -Directory -ErrorAction SilentlyContinue |
        Sort-Object -Property Name
)

if (-not $sourceSkills -or $sourceSkills.Count -eq 0) {
    Write-Host "WARNING: No skills found in $sourceSkillsDir" -ForegroundColor Yellow
    exit 0
}

$validSourceSkills = @()
foreach ($sourceSkill in $sourceSkills) {
    $sourceSkillMd = Join-Path $sourceSkill.FullName "SKILL.md"
    if (-not (Test-Path -LiteralPath $sourceSkillMd)) {
        Write-Host "Skipped: $($sourceSkill.Name) (missing SKILL.md)" -ForegroundColor Yellow
        continue
    }

    $validSourceSkills += $sourceSkill
}

if ($validSourceSkills.Count -eq 0) {
    Write-Host "WARNING: No valid skills found in $sourceSkillsDir" -ForegroundColor Yellow
    exit 0
}

$selectedSkills = @()
if ($Skill) {
    $requestedNames = @(
        $Skill |
            ForEach-Object { $_ -split "," } |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
    )
    $unknownNames = @(
        $requestedNames |
            Where-Object { $_ -notin $validSourceSkills.Name } |
            Sort-Object -Unique
    )
    if ($unknownNames.Count -gt 0) {
        Write-Host "ERROR: Unknown skill(s): $($unknownNames -join ', ')" -ForegroundColor Red
        Write-Host "Available skills: $($validSourceSkills.Name -join ', ')" -ForegroundColor Gray
        exit 1
    }

    $selectedSkills = @(
        $validSourceSkills | Where-Object { $_.Name -in $requestedNames }
    )
} elseif ($Force) {
    $selectedSkills = $validSourceSkills
} else {
    Write-Host "Available skills:" -ForegroundColor Green
    for ($index = 0; $index -lt $validSourceSkills.Count; $index++) {
        $sourceSkill = $validSourceSkills[$index]
        $targetPath = Join-Path $targetSkillsDir $sourceSkill.Name
        $status = if (Test-Path -LiteralPath $targetPath) {
            " (already installed)"
        } else {
            ""
        }
        $color = if ($status) { "Yellow" } else { "Gray" }
        Write-Host "  [$($index + 1)] $($sourceSkill.Name)$status" -ForegroundColor $color
    }
    Write-Host ""

    $response = Read-Host "Select skills by number or name (comma-separated), or enter 'all'"
    if ([string]::IsNullOrWhiteSpace($response)) {
        Write-Host "Installation cancelled." -ForegroundColor Yellow
        exit 0
    }

    $selections = @(
        $response -split "," |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
    )
    if ($selections -contains "all") {
        $selectedSkills = $validSourceSkills
    } else {
        $invalidSelections = @()
        $selectedNames = @()
        foreach ($selection in $selections) {
            if ($selection -match "^\d+$") {
                $selectedIndex = [int]$selection - 1
                if ($selectedIndex -lt 0 -or $selectedIndex -ge $validSourceSkills.Count) {
                    $invalidSelections += $selection
                    continue
                }
                $selectedNames += $validSourceSkills[$selectedIndex].Name
            } elseif ($selection -in $validSourceSkills.Name) {
                $selectedNames += $selection
            } else {
                $invalidSelections += $selection
            }
        }

        if ($invalidSelections.Count -gt 0) {
            Write-Host "ERROR: Invalid selection(s): $($invalidSelections -join ', ')" -ForegroundColor Red
            exit 1
        }

        $selectedSkills = @(
            $validSourceSkills |
                Where-Object { $_.Name -in $selectedNames }
        )
    }
}

if ($selectedSkills.Count -eq 0) {
    Write-Host "No skills selected. Nothing to install." -ForegroundColor Yellow
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

Write-Host ""
Write-Host "Selected $($selectedSkills.Count) skill(s):" -ForegroundColor Green
$selectedSkills | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
Write-Host ""

$installed = 0
$skipped = 0

foreach ($selectedSkill in $selectedSkills) {
    $targetPath = Join-Path $targetSkillsDir $selectedSkill.Name
    if (Test-Path $targetPath) {
        if (-not $Force) {
            $response = Read-Host "Skill '$($selectedSkill.Name)' already exists. Overwrite? [y/N]"
            if ($response -notmatch "^[Yy]") {
                Write-Host "  Skipped: $($selectedSkill.Name)" -ForegroundColor Yellow
                $skipped++
                continue
            }
        }
        Remove-Item -Path $targetPath -Recurse -Force
    }

    Copy-Item -Path $selectedSkill.FullName -Destination $targetPath -Recurse -Force
    $generatedDirectories = @(
        Get-ChildItem -LiteralPath $targetPath -Directory -Recurse -Force |
            Where-Object { $_.Name -in @("bin", "obj") } |
            Sort-Object -Property FullName -Descending
    )
    foreach ($generatedDirectory in $generatedDirectories) {
        Remove-Item -LiteralPath $generatedDirectory.FullName -Recurse -Force
    }
    Write-Host "  Installed: $($selectedSkill.Name)" -ForegroundColor Green
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
