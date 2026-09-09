<#
.SYNOPSIS
    Installs commandline-crew for Copilot CLI, OpenCode, or both.
#>

param(
    [ValidateSet("copilot", "opencode", "both")]
    [string]$Runtime,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Resolve-Runtime {
    if ($Runtime) { return $Runtime.ToLowerInvariant() }
    while ($true) {
        $value = (Read-Host "Install for Copilot, OpenCode, or both? [copilot/opencode/both]").Trim().ToLowerInvariant()
        if ($value -in @("c", "copilot")) { return "copilot" }
        if ($value -in @("o", "opencode")) { return "opencode" }
        if ($value -in @("b", "both")) { return "both" }
        Write-Host "Please enter copilot, opencode, or both." -ForegroundColor Yellow
    }
}

function Get-UserHome {
    if ($env:USERPROFILE) { return $env:USERPROFILE }
    if ($env:HOME) { return $env:HOME }
    throw "Neither USERPROFILE nor HOME is set."
}

function Get-OpenCodeRoot {
    $root = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path (Get-UserHome) ".config" }
    return Join-Path $root "opencode"
}

function Read-JsonObject {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "JSON file not found: $Path" }
    try { $value = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
    catch { throw "Malformed JSON in '$Path': $($_.Exception.Message)" }
    if ($value -isnot [PSCustomObject]) { throw "JSON root must be an object: $Path" }
    return $value
}

function Write-JsonSafely {
    param($Value, [string]$Path)
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $temporaryPath = Join-Path $parent (".$([IO.Path]::GetRandomFileName())")
    try {
        $encoding = New-Object Text.UTF8Encoding -ArgumentList $false
        $json = ($Value | ConvertTo-Json -Depth 100) + [Environment]::NewLine
        [IO.File]::WriteAllText($temporaryPath, $json, $encoding)
        Copy-Item -LiteralPath $temporaryPath -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
    }
}

function Get-Manifest {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        $manifest = Read-JsonObject $Path
    } else {
        $manifest = [PSCustomObject]@{
            version = 1
            agents = [PSCustomObject]@{}
            mcp = [PSCustomObject]@{}
            skills = [PSCustomObject]@{}
        }
    }
    foreach ($name in @("agents", "mcp", "skills")) {
        if (-not $manifest.PSObject.Properties[$name]) {
            $manifest | Add-Member -MemberType NoteProperty -Name $name -Value ([PSCustomObject]@{})
        } elseif ($manifest.$name -isnot [PSCustomObject]) {
            throw "Manifest category '$name' must be an object: $Path"
        }
    }
    return $manifest
}

function Set-Ownership {
    param($Manifest, [string]$Category, [string]$Name, $Value, [string]$ManifestPath)
    if ($Manifest.$Category.PSObject.Properties[$Name]) {
        $Manifest.$Category.PSObject.Properties.Remove($Name)
    }
    $Manifest.$Category | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    foreach ($categoryName in @("agents", "mcp", "skills")) {
        if (
            $Manifest.PSObject.Properties[$categoryName] -and
            @($Manifest.$categoryName.PSObject.Properties).Count -eq 0
        ) {
            $Manifest.PSObject.Properties.Remove($categoryName)
        }
    }
    Write-JsonSafely $Manifest $ManifestPath
    foreach ($categoryName in @("agents", "mcp", "skills")) {
        if (-not $Manifest.PSObject.Properties[$categoryName]) {
            $Manifest | Add-Member -MemberType NoteProperty -Name $categoryName -Value ([PSCustomObject]@{})
        }
    }
}

function Confirm-Overwrite {
    param([string]$Label)
    if ($Force) { return $true }
    return (Read-Host "$Label already exists. Overwrite? [y/N]") -match "^[Yy]"
}

function Install-Runtime {
    param(
        [string]$RuntimeName,
        [string]$SourceAgents,
        [string]$AgentFilter,
        [string]$SourceConfig,
        [string]$MapName,
        [string]$TargetRoot,
        [string]$TargetConfig
    )

    if (-not (Test-Path -LiteralPath $SourceAgents -PathType Container)) {
        throw "$RuntimeName agent source directory not found: $SourceAgents"
    }
    $agentFiles = @(Get-ChildItem -LiteralPath $SourceAgents -Filter $AgentFilter -File)
    if ($agentFiles.Count -eq 0) { throw "No $RuntimeName agent files found in $SourceAgents" }

    $source = Read-JsonObject $SourceConfig
    $sourceMapProperty = $source.PSObject.Properties[$MapName]
    if (-not $sourceMapProperty -or $sourceMapProperty.Value -isnot [PSCustomObject]) {
        throw "'$MapName' must be an object in $SourceConfig"
    }

    New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null
    $manifestPath = Join-Path $TargetRoot "commandline-crew-manifest.json"
    $manifest = Get-Manifest $manifestPath
    $target = if (Test-Path -LiteralPath $TargetConfig) {
        Read-JsonObject $TargetConfig
    } else {
        [PSCustomObject]@{}
    }
    if (-not (Test-Path -LiteralPath $TargetConfig) -and $source.PSObject.Properties['$schema']) {
        $target | Add-Member -MemberType NoteProperty -Name '$schema' -Value $source.'$schema'
    }
    if (-not $target.PSObject.Properties[$MapName]) {
        $target | Add-Member -MemberType NoteProperty -Name $MapName -Value ([PSCustomObject]@{})
    } elseif ($target.$MapName -isnot [PSCustomObject]) {
        throw "'$MapName' must be an object in $TargetConfig"
    }

    $mergedNames = @()
    foreach ($entry in $source.$MapName.PSObject.Properties) {
        if ($target.$MapName.PSObject.Properties[$entry.Name]) {
            if (-not (Confirm-Overwrite "  $RuntimeName MCP entry '$($entry.Name)'")) {
                Write-Host "  Skipped MCP entry: $($entry.Name)" -ForegroundColor Yellow
                continue
            }
            $target.$MapName.PSObject.Properties.Remove($entry.Name)
        }
        $target.$MapName | Add-Member -MemberType NoteProperty -Name $entry.Name -Value $entry.Value
        $mergedNames += $entry.Name
    }
    if ($mergedNames.Count -gt 0) {
        Write-JsonSafely $target $TargetConfig
        foreach ($name in $mergedNames) {
            Set-Ownership $manifest "mcp" $name $target.$MapName.PSObject.Properties[$name].Value $manifestPath
            Write-Host "  Merged MCP entry: $name" -ForegroundColor Green
        }
    }

    $targetAgents = Join-Path $TargetRoot "agents"
    New-Item -ItemType Directory -Path $targetAgents -Force | Out-Null
    foreach ($file in $agentFiles) {
        $destination = Join-Path $targetAgents $file.Name
        if ((Test-Path -LiteralPath $destination) -and -not (Confirm-Overwrite "  $RuntimeName agent '$($file.Name)'")) {
            Write-Host "  Skipped agent: $($file.Name)" -ForegroundColor Yellow
            continue
        }
        Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
        $record = [PSCustomObject]@{
            sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        Set-Ownership $manifest "agents" $file.Name $record $manifestPath
        Write-Host "  Installed agent: $($file.Name)" -ForegroundColor Green
    }
}

$selectedRuntime = Resolve-Runtime
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$userHome = Get-UserHome

Write-Host "Commandline Crew - Installer ($selectedRuntime)" -ForegroundColor Cyan

if ($selectedRuntime -in @("copilot", "both")) {
    $root = Join-Path $userHome ".copilot"
    Install-Runtime `
        -RuntimeName "Copilot" `
        -SourceAgents (Join-Path $scriptDir ".github/agents") `
        -AgentFilter "*.agent.md" `
        -SourceConfig (Join-Path $scriptDir ".copilot/mcp-config.json") `
        -MapName "mcpServers" `
        -TargetRoot $root `
        -TargetConfig (Join-Path $root "mcp-config.json")
}

if ($selectedRuntime -in @("opencode", "both")) {
    $root = Get-OpenCodeRoot
    Install-Runtime `
        -RuntimeName "OpenCode" `
        -SourceAgents (Join-Path $scriptDir ".opencode/agents") `
        -AgentFilter "*.md" `
        -SourceConfig (Join-Path $scriptDir ".opencode/opencode.json") `
        -MapName "mcp" `
        -TargetRoot $root `
        -TargetConfig (Join-Path $root "opencode.json")
}

Write-Host "Installation complete for: $selectedRuntime" -ForegroundColor Cyan
