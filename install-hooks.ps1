<#
.SYNOPSIS
    Installs Copilot hooks observability tooling into a target repository.

.DESCRIPTION
    Copies the hooks/ Python scripts and hooks.json configuration into
    the target repository. After installation the repository will log all
    Copilot agent lifecycle events (sessions, tool uses, prompts, errors)
    to observability/hooks.db.

    Two hooks.json files are written:
      {target}/hooks.json            -- used by Copilot CLI (cwd-based loading)
      {target}/.github/hooks/hooks.json -- used by Copilot coding agent

.PARAMETER TargetRepo
    Path to the target repository. Must be an existing directory.

.PARAMETER Force
    Overwrite existing files without prompting.

.EXAMPLE
    .\install-hooks.ps1 -TargetRepo C:\projects\my-app
    .\install-hooks.ps1 -TargetRepo C:\projects\my-app -Force
#>

param(
    [Parameter(Mandatory)]
    [string]$TargetRepo,

    [switch]$Force
)

$ErrorActionPreference = "Stop"

$scriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceHooks  = Join-Path $scriptDir "hooks"
$sourceJson   = Join-Path $scriptDir "hooks.json"

Write-Host "Copilot Hooks Observability - Installer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# --- Validate target ---
if (-not (Test-Path $TargetRepo -PathType Container)) {
    Write-Host "ERROR: Target repository not found: $TargetRepo" -ForegroundColor Red
    exit 1
}

$TargetRepo = Resolve-Path $TargetRepo | Select-Object -ExpandProperty Path
Write-Host "Target repository: $TargetRepo" -ForegroundColor Gray
Write-Host ""

# --- Copy hooks/ scripts ---
Write-Host "Python Hook Scripts" -ForegroundColor Cyan
Write-Host "-------------------" -ForegroundColor Cyan

$targetHooksDir = Join-Path $TargetRepo "hooks"
if (-not (Test-Path $targetHooksDir)) {
    New-Item -ItemType Directory -Path $targetHooksDir -Force | Out-Null
    Write-Host "  Created: hooks/" -ForegroundColor Yellow
}

$pyFiles = Get-ChildItem -Path $sourceHooks -Filter "*.py"
$installed = 0
$skipped   = 0

foreach ($file in $pyFiles) {
    $dest   = Join-Path $targetHooksDir $file.Name
    $exists = Test-Path $dest

    if ($exists -and -not $Force) {
        $response = Read-Host "  '$($file.Name)' already exists. Overwrite? [y/N]"
        if ($response -notmatch "^[Yy]") {
            Write-Host "  Skipped: $($file.Name)" -ForegroundColor Yellow
            $skipped++
            continue
        }
    }

    Copy-Item -Path $file.FullName -Destination $dest -Force
    Write-Host "  Installed: $($file.Name)" -ForegroundColor Green
    $installed++
}

Write-Host "  Scripts: $installed installed, $skipped skipped" -ForegroundColor $(if ($skipped -gt 0) { 'Yellow' } else { 'Green' })
Write-Host ""

# --- Write hooks.json (CLI, repo root) ---
Write-Host "hooks.json (Copilot CLI)" -ForegroundColor Cyan
Write-Host "------------------------" -ForegroundColor Cyan

$targetJsonCli = Join-Path $TargetRepo "hooks.json"
$writeCliJson  = $true

if ((Test-Path $targetJsonCli) -and -not $Force) {
    $response = Read-Host "  hooks.json already exists at repo root. Overwrite? [y/N]"
    if ($response -notmatch "^[Yy]") {
        Write-Host "  Skipped: hooks.json (CLI)" -ForegroundColor Yellow
        $writeCliJson = $false
    }
}

if ($writeCliJson) {
    Copy-Item -Path $sourceJson -Destination $targetJsonCli -Force
    Write-Host "  Installed: hooks.json" -ForegroundColor Green
}
Write-Host ""

# --- Write .github/hooks/hooks.json (coding agent) ---
Write-Host "hooks.json (Coding Agent)" -ForegroundColor Cyan
Write-Host "-------------------------" -ForegroundColor Cyan

$targetGhHooksDir = Join-Path $TargetRepo ".github" "hooks"
if (-not (Test-Path $targetGhHooksDir)) {
    New-Item -ItemType Directory -Path $targetGhHooksDir -Force | Out-Null
    Write-Host "  Created: .github/hooks/" -ForegroundColor Yellow
}

$targetJsonAgent = Join-Path $targetGhHooksDir "hooks.json"
$writeAgentJson  = $true

if ((Test-Path $targetJsonAgent) -and -not $Force) {
    $response = Read-Host "  .github/hooks/hooks.json already exists. Overwrite? [y/N]"
    if ($response -notmatch "^[Yy]") {
        Write-Host "  Skipped: .github/hooks/hooks.json" -ForegroundColor Yellow
        $writeAgentJson = $false
    }
}

if ($writeAgentJson) {
    Copy-Item -Path $sourceJson -Destination $targetJsonAgent -Force
    Write-Host "  Installed: .github/hooks/hooks.json" -ForegroundColor Green
}
Write-Host ""

# --- .gitignore reminder ---
$gitignorePath = Join-Path $TargetRepo ".gitignore"
if (Test-Path $gitignorePath) {
    $gitignoreContent = Get-Content $gitignorePath -Raw
    if ($gitignoreContent -notmatch "observability") {
        Write-Host "TIP: Add the following to $TargetRepo\.gitignore to exclude the database:" -ForegroundColor Yellow
        Write-Host "  observability/" -ForegroundColor White
        Write-Host ""
    }
}

Write-Host "Installation complete!" -ForegroundColor Cyan
Write-Host ""
Write-Host "Run a Copilot session in $TargetRepo then view reports with:" -ForegroundColor Gray
Write-Host "  python hooks/report.py sessions" -ForegroundColor White
Write-Host "  python hooks/report.py tools" -ForegroundColor White
Write-Host "  python hooks/report.py files" -ForegroundColor White
Write-Host "  python hooks/report.py errors" -ForegroundColor White
Write-Host "  python hooks/report.py tokens" -ForegroundColor White
Write-Host "  python hooks/report.py prompts" -ForegroundColor White
Write-Host ""
Write-Host "To uninstall: .\uninstall-hooks.ps1 -TargetRepo $TargetRepo" -ForegroundColor Gray
