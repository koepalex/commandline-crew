<#
.SYNOPSIS
    Removes Copilot hooks observability tooling from a target repository.

.DESCRIPTION
    Removes the hooks/ Python scripts, hooks.json at the repo root, and
    .github/hooks/hooks.json that were installed by install-hooks.ps1.

    The database at observability/hooks.db is NOT deleted automatically
    to preserve collected observability data. Use -PurgeData to remove it too.

.PARAMETER TargetRepo
    Path to the target repository.

.PARAMETER Force
    Remove files without prompting.

.PARAMETER PurgeData
    Also delete the observability/ directory and its database.

.EXAMPLE
    .\uninstall-hooks.ps1 -TargetRepo C:\projects\my-app
    .\uninstall-hooks.ps1 -TargetRepo C:\projects\my-app -Force
    .\uninstall-hooks.ps1 -TargetRepo C:\projects\my-app -Force -PurgeData
#>

param(
    [Parameter(Mandatory)]
    [string]$TargetRepo,

    [switch]$Force,

    [switch]$PurgeData
)

$ErrorActionPreference = "Stop"

Write-Host "Copilot Hooks Observability - Uninstaller" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $TargetRepo -PathType Container)) {
    Write-Host "ERROR: Target repository not found: $TargetRepo" -ForegroundColor Red
    exit 1
}

$TargetRepo = Resolve-Path $TargetRepo | Select-Object -ExpandProperty Path
Write-Host "Target repository: $TargetRepo" -ForegroundColor Gray
Write-Host ""

function Remove-IfExists {
    param([string]$Path, [string]$Label)
    if (Test-Path $Path) {
        if (-not $Force) {
            $response = Read-Host "  Remove '$Label'? [y/N]"
            if ($response -notmatch "^[Yy]") {
                Write-Host "  Skipped: $Label" -ForegroundColor Yellow
                return
            }
        }
        Remove-Item -Path $Path -Force -Recurse
        Write-Host "  Removed: $Label" -ForegroundColor Green
    } else {
        Write-Host "  Not found (skipped): $Label" -ForegroundColor Gray
    }
}

# --- Remove hooks/ directory ---
Write-Host "Python Hook Scripts" -ForegroundColor Cyan
Write-Host "-------------------" -ForegroundColor Cyan

$hooksDir = Join-Path $TargetRepo "hooks"
if (Test-Path $hooksDir) {
    $scriptNames = @(
        "db.py","session_start.py","session_end.py","user_prompt.py",
        "pre_tool_use.py","post_tool_use.py","error_occurred.py","report.py"
    )
    foreach ($name in $scriptNames) {
        Remove-IfExists -Path (Join-Path $hooksDir $name) -Label "hooks/$name"
    }

    # Remove the directory if now empty
    $remaining = Get-ChildItem -Path $hooksDir -ErrorAction SilentlyContinue
    if (-not $remaining) {
        Remove-Item -Path $hooksDir -Force
        Write-Host "  Removed: hooks/ (empty)" -ForegroundColor Green
    } else {
        Write-Host "  Note: hooks/ directory kept (contains other files)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  Not found (skipped): hooks/" -ForegroundColor Gray
}
Write-Host ""

# --- Remove hooks.json files ---
Write-Host "hooks.json Files" -ForegroundColor Cyan
Write-Host "----------------" -ForegroundColor Cyan

Remove-IfExists -Path (Join-Path $TargetRepo "hooks.json")             -Label "hooks.json (CLI)"
Remove-IfExists -Path (Join-Path $TargetRepo ".github\hooks\hooks.json") -Label ".github/hooks/hooks.json (agent)"
Write-Host ""

# --- Optionally purge data ---
if ($PurgeData) {
    Write-Host "Observability Data" -ForegroundColor Cyan
    Write-Host "------------------" -ForegroundColor Cyan
    Remove-IfExists -Path (Join-Path $TargetRepo "observability") -Label "observability/"
    Write-Host ""
} else {
    $dataDir = Join-Path $TargetRepo "observability"
    if (Test-Path $dataDir) {
        Write-Host "NOTE: Database preserved at: $dataDir" -ForegroundColor Yellow
        Write-Host "      Use -PurgeData to delete it." -ForegroundColor Yellow
        Write-Host ""
    }
}

Write-Host "Uninstall complete!" -ForegroundColor Cyan
