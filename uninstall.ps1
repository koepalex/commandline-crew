<#
.SYNOPSIS
    Uninstalls resources owned by commandline-crew from Copilot CLI, OpenCode, or both.
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
        $value = (Read-Host "Uninstall from Copilot, OpenCode, or both? [copilot/opencode/both]").Trim().ToLowerInvariant()
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
    $manifest = Read-JsonObject $Path
    foreach ($name in @("agents", "mcp", "skills")) {
        if (-not $manifest.PSObject.Properties[$name]) {
            $manifest | Add-Member -MemberType NoteProperty -Name $name -Value ([PSCustomObject]@{})
        } elseif ($manifest.$name -isnot [PSCustomObject]) {
            throw "Manifest category '$name' must be an object: $Path"
        }
    }
    return $manifest
}

function Test-JsonEqual {
    param($Left, $Right)
    if ($null -eq $Left -or $null -eq $Right) { return $null -eq $Left -and $null -eq $Right }
    if ($Left -is [array] -or $Right -is [array]) {
        $leftItems = @($Left); $rightItems = @($Right)
        if ($leftItems.Count -ne $rightItems.Count) { return $false }
        for ($index = 0; $index -lt $leftItems.Count; $index++) {
            if (-not (Test-JsonEqual $leftItems[$index] $rightItems[$index])) { return $false }
        }
        return $true
    }
    if ($Left -is [PSCustomObject] -or $Right -is [PSCustomObject]) {
        if ($Left -isnot [PSCustomObject] -or $Right -isnot [PSCustomObject]) { return $false }
        $leftNames = @(
            $Left.PSObject.Properties |
                ForEach-Object { $_.Name } |
                Sort-Object
        )
        $rightNames = @(
            $Right.PSObject.Properties |
                ForEach-Object { $_.Name } |
                Sort-Object
        )
        if (($leftNames -join "`n") -ne ($rightNames -join "`n")) { return $false }
        foreach ($name in $leftNames) {
            if (-not (Test-JsonEqual $Left.$name $Right.$name)) { return $false }
        }
        return $true
    }
    if ($Left.GetType() -ne $Right.GetType()) { return $false }
    return $Left -eq $Right
}

function Confirm-Removal {
    param([string]$Label)
    if ($Force) { return $true }
    return (Read-Host "Remove $Label? [y/N]") -match "^[Yy]"
}

function Save-Manifest {
    param($Manifest, [string]$Path)
    foreach ($categoryName in @("agents", "mcp", "skills")) {
        if (
            $Manifest.PSObject.Properties[$categoryName] -and
            @($Manifest.$categoryName.PSObject.Properties).Count -eq 0
        ) {
            $Manifest.PSObject.Properties.Remove($categoryName)
        }
    }
    $ownedCategories = @(
        $Manifest.PSObject.Properties |
            ForEach-Object { $_.Name } |
            Where-Object { $_ -ne "version" }
    )
    if ($ownedCategories.Count -eq 0) {
        Remove-Item -LiteralPath $Path -Force
    } else {
        Write-JsonSafely $Manifest $Path
    }
    foreach ($categoryName in @("agents", "mcp", "skills")) {
        if (-not $Manifest.PSObject.Properties[$categoryName]) {
            $Manifest | Add-Member -MemberType NoteProperty -Name $categoryName -Value ([PSCustomObject]@{})
        }
    }
}

function Drop-Ownership {
    param($Manifest, [string]$Category, [string]$Name, [string]$ManifestPath)
    $Manifest.$Category.PSObject.Properties.Remove($Name)
    Save-Manifest $Manifest $ManifestPath
}

function Uninstall-Runtime {
    param(
        [string]$RuntimeName,
        [string]$TargetRoot,
        [string]$MapName,
        [string]$TargetConfig
    )

    $manifestPath = Join-Path $TargetRoot "commandline-crew-manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        Write-Host "No $RuntimeName ownership manifest found; nothing will be removed." -ForegroundColor Yellow
        return
    }
    $manifest = Get-Manifest $manifestPath

    $target = if (Test-Path -LiteralPath $TargetConfig) { Read-JsonObject $TargetConfig } else { $null }
    if ($target -and $target.PSObject.Properties[$MapName] -and $target.$MapName -isnot [PSCustomObject]) {
        throw "'$MapName' must be an object in $TargetConfig"
    }
    foreach ($property in @($manifest.mcp.PSObject.Properties)) {
        $name = $property.Name
        $targetEntry = if ($target -and $target.PSObject.Properties[$MapName]) {
            $target.$MapName.PSObject.Properties[$name]
        } else {
            $null
        }
        if (-not $targetEntry -or -not (Test-JsonEqual $property.Value $targetEntry.Value)) {
            Write-Host "  Preserved modified or missing MCP entry and dropped ownership: $name" -ForegroundColor Yellow
            Drop-Ownership $manifest "mcp" $name $manifestPath
            continue
        }
        if (-not (Confirm-Removal "$RuntimeName MCP entry '$name'")) { continue }
        $target.$MapName.PSObject.Properties.Remove($name)
        if (@($target.$MapName.PSObject.Properties).Count -eq 0) { $target.PSObject.Properties.Remove($MapName) }
        if (@($target.PSObject.Properties).Count -eq 0) {
            Remove-Item -LiteralPath $TargetConfig -Force
            $target = $null
        } else {
            Write-JsonSafely $target $TargetConfig
        }
        Drop-Ownership $manifest "mcp" $name $manifestPath
        Write-Host "  Removed MCP entry: $name" -ForegroundColor Green
    }

    foreach ($property in @($manifest.agents.PSObject.Properties)) {
        $name = $property.Name
        $targetPath = Join-Path (Join-Path $TargetRoot "agents") $name
        if (
            -not (Test-Path -LiteralPath $targetPath -PathType Leaf) -or
            -not $property.Value.PSObject.Properties["sha256"] -or
            (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne
                ([string]$property.Value.sha256).ToLowerInvariant()
        ) {
            Write-Host "  Preserved modified or missing agent and dropped ownership: $name" -ForegroundColor Yellow
            Drop-Ownership $manifest "agents" $name $manifestPath
            continue
        }
        if (-not (Confirm-Removal "$RuntimeName agent '$name'")) { continue }
        Remove-Item -LiteralPath $targetPath -Force
        Drop-Ownership $manifest "agents" $name $manifestPath
        Write-Host "  Removed agent: $name" -ForegroundColor Green
    }

    $agentsDirectory = Join-Path $TargetRoot "agents"
    if ((Test-Path -LiteralPath $agentsDirectory) -and @(Get-ChildItem -LiteralPath $agentsDirectory -Force).Count -eq 0) {
        Remove-Item -LiteralPath $agentsDirectory -Force
    }
}

$selectedRuntime = Resolve-Runtime
$userHome = Get-UserHome

if ($selectedRuntime -in @("copilot", "both")) {
    $root = Join-Path $userHome ".copilot"
    Uninstall-Runtime `
        -RuntimeName "Copilot" `
        -TargetRoot $root `
        -MapName "mcpServers" `
        -TargetConfig (Join-Path $root "mcp-config.json")
}
if ($selectedRuntime -in @("opencode", "both")) {
    $root = Get-OpenCodeRoot
    Uninstall-Runtime `
        -RuntimeName "OpenCode" `
        -TargetRoot $root `
        -MapName "mcp" `
        -TargetConfig (Join-Path $root "opencode.json")
}

Write-Host "Uninstall complete for: $selectedRuntime" -ForegroundColor Cyan
