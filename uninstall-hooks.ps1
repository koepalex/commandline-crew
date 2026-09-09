<#
.SYNOPSIS
    Uninstalls hooks observability resources owned by commandline-crew.
#>

param(
    [Parameter(Mandatory)]
    [string]$TargetRepo,
    [ValidateSet("copilot", "opencode", "both")]
    [string]$Runtime,
    [switch]$Force,
    [switch]$PurgeData
)

$ErrorActionPreference = "Stop"

function Resolve-Runtime {
    if ($Runtime) { return $Runtime.ToLowerInvariant() }
    while ($true) {
        $value = (Read-Host "Uninstall hooks from Copilot, OpenCode, or both? [copilot/opencode/both]").Trim().ToLowerInvariant()
        if ($value -in @("c", "copilot")) { return "copilot" }
        if ($value -in @("o", "opencode")) { return "opencode" }
        if ($value -in @("b", "both")) { return "both" }
        Write-Host "Please enter copilot, opencode, or both." -ForegroundColor Yellow
    }
}

function Read-JsonObject {
    param([string]$Path)
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

function Get-Manifest {
    param([string]$Path)
    $manifest = Read-JsonObject $Path
    foreach ($name in @("copilotFiles", "opencodeFiles", "copilotHooksRoot", "copilotHooksAgent", "createdConfigs")) {
        if (-not $manifest.PSObject.Properties[$name]) {
            $manifest | Add-Member -MemberType NoteProperty -Name $name -Value ([PSCustomObject]@{})
        } elseif ($manifest.$name -isnot [PSCustomObject]) {
            throw "Manifest category '$name' must be an object: $Path"
        }
    }
    return $manifest
}

function Save-Manifest {
    param($Manifest, [string]$Path)
    foreach ($categoryName in @(
        "copilotFiles", "opencodeFiles", "copilotHooksRoot", "copilotHooksAgent", "createdConfigs"
    )) {
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
        $directory = Split-Path -Parent $Path
        if ((Test-Path -LiteralPath $directory) -and @(Get-ChildItem -LiteralPath $directory -Force).Count -eq 0) {
            Remove-Item -LiteralPath $directory -Force
        }
    } else {
        Write-JsonSafely $Manifest $Path
    }
    foreach ($categoryName in @(
        "copilotFiles", "opencodeFiles", "copilotHooksRoot", "copilotHooksAgent", "createdConfigs"
    )) {
        if (-not $Manifest.PSObject.Properties[$categoryName]) {
            $Manifest | Add-Member -MemberType NoteProperty -Name $categoryName -Value ([PSCustomObject]@{})
        }
    }
}

function Confirm-Removal {
    param([string]$Label)
    if ($Force) { return $true }
    return (Read-Host "Remove '$Label'? [y/N]") -match "^[Yy]"
}

function Remove-EmptyDirectory {
    param([string]$Path)
    if (
        (Test-Path -LiteralPath $Path -PathType Container) -and
        @(Get-ChildItem -LiteralPath $Path -Force).Count -eq 0
    ) {
        Remove-Item -LiteralPath $Path -Force
    }
}

function Find-EqualIndex {
    param([array]$Items, $Value)
    for ($index = 0; $index -lt $Items.Count; $index++) {
        if (Test-JsonEqual $Items[$index] $Value) { return $index }
    }
    return -1
}

function Test-HooksConfigEmpty {
    param($Config)
    $otherProperties = @(
        $Config.PSObject.Properties |
            ForEach-Object { $_.Name } |
            Where-Object { $_ -notin @("version", "hooks") }
    )
    if ($otherProperties.Count -gt 0) { return $false }
    if ($Config.PSObject.Properties["hooks"] -and @($Config.hooks.PSObject.Properties).Count -gt 0) { return $false }
    return $true
}

function Remove-HookEntries {
    param(
        [string]$RelativePath,
        [string]$Category,
        $Manifest,
        [string]$ManifestPath,
        [string]$TargetRepo
    )
    $ownedEvents = @($Manifest.$Category.PSObject.Properties)
    if ($ownedEvents.Count -eq 0) { return }
    $targetPath = Join-Path $TargetRepo $RelativePath
    if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
        foreach ($eventProperty in $ownedEvents) {
            $Manifest.$Category.PSObject.Properties.Remove($eventProperty.Name)
        }
        $Manifest.createdConfigs.PSObject.Properties.Remove($RelativePath)
        Save-Manifest $Manifest $ManifestPath
        Write-Host "  Config missing; dropped ownership: $RelativePath" -ForegroundColor Yellow
        return
    }
    $target = Read-JsonObject $targetPath
    $targetHooksValid = $target.PSObject.Properties["hooks"] -and $target.hooks -is [PSCustomObject]
    $targetChanged = $false
    foreach ($eventProperty in $ownedEvents) {
        $event = $eventProperty.Name
        $remainingRecords = @()
        foreach ($recordedHook in @($eventProperty.Value)) {
            $targetEvent = if ($targetHooksValid) { $target.hooks.PSObject.Properties[$event] } else { $null }
            $items = if ($targetEvent -and $targetEvent.Value -is [array]) { @($targetEvent.Value) } else { @() }
            $index = Find-EqualIndex $items $recordedHook
            if ($index -lt 0) {
                Write-Host "  Hook modified or missing; dropped ownership: $RelativePath [$event]" -ForegroundColor Yellow
                continue
            }
            if (-not (Confirm-Removal "$RelativePath hook '$event'")) {
                $remainingRecords += $recordedHook
                continue
            }
            $newItems = @()
            for ($itemIndex = 0; $itemIndex -lt $items.Count; $itemIndex++) {
                if ($itemIndex -ne $index) { $newItems += $items[$itemIndex] }
            }
            if ($newItems.Count -eq 0) {
                $target.hooks.PSObject.Properties.Remove($event)
            } else {
                $target.hooks.PSObject.Properties[$event].Value = $newItems
            }
            $targetChanged = $true
        }
        if ($remainingRecords.Count -eq 0) {
            $Manifest.$Category.PSObject.Properties.Remove($event)
        } else {
            $Manifest.$Category.PSObject.Properties[$event].Value = $remainingRecords
        }
    }
    if ($targetChanged -and $target.PSObject.Properties["hooks"] -and @($target.hooks.PSObject.Properties).Count -eq 0) {
        $target.PSObject.Properties.Remove("hooks")
    }

    $created = $null -ne $Manifest.createdConfigs.PSObject.Properties[$RelativePath]
    if ($created -and (Test-HooksConfigEmpty $target)) {
        Remove-Item -LiteralPath $targetPath -Force
        $Manifest.createdConfigs.PSObject.Properties.Remove($RelativePath)
        Write-Host "  Removed empty installed config: $RelativePath" -ForegroundColor Green
    } elseif ($targetChanged) {
        Write-JsonSafely $target $targetPath
    }
    if (@($Manifest.$Category.PSObject.Properties).Count -eq 0) {
        $Manifest.createdConfigs.PSObject.Properties.Remove($RelativePath)
    }
    Save-Manifest $Manifest $ManifestPath
}

function Remove-OwnedFiles {
    param(
        [string]$Category,
        [string]$OtherCategory,
        $Manifest,
        [string]$ManifestPath,
        [string]$TargetRepo
    )
    foreach ($property in @($Manifest.$Category.PSObject.Properties)) {
        $relative = $property.Name
        $targetPath = Join-Path $TargetRepo $relative
        if (
            -not (Test-Path -LiteralPath $targetPath -PathType Leaf) -or
            -not $property.Value.PSObject.Properties["sha256"] -or
            (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne
                ([string]$property.Value.sha256).ToLowerInvariant()
        ) {
            $Manifest.$Category.PSObject.Properties.Remove($relative)
            Save-Manifest $Manifest $ManifestPath
            Write-Host "  Preserved modified or missing file and dropped ownership: $relative" -ForegroundColor Yellow
            continue
        }
        if ($Manifest.$OtherCategory.PSObject.Properties[$relative]) {
            $Manifest.$Category.PSObject.Properties.Remove($relative)
            Save-Manifest $Manifest $ManifestPath
            Write-Host "  Retained shared file for other runtime: $relative" -ForegroundColor Gray
            continue
        }
        if (-not (Confirm-Removal $relative)) { continue }
        Remove-Item -LiteralPath $targetPath -Force
        $Manifest.$Category.PSObject.Properties.Remove($relative)
        Save-Manifest $Manifest $ManifestPath
        Write-Host "  Removed: $relative" -ForegroundColor Green
    }
}

$selectedRuntime = Resolve-Runtime
if (-not (Test-Path -LiteralPath $TargetRepo -PathType Container)) { throw "Target repository not found: $TargetRepo" }
$TargetRepo = (Resolve-Path -LiteralPath $TargetRepo).Path
$manifestPath = Join-Path $TargetRepo ".commandline-crew/manifest.json"

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    Write-Host "No hook ownership manifest found; no installed resources will be removed." -ForegroundColor Yellow
} else {
    $manifest = Get-Manifest $manifestPath
    if ($selectedRuntime -in @("copilot", "both")) {
        Remove-HookEntries "hooks.json" "copilotHooksRoot" $manifest $manifestPath $TargetRepo
        Remove-HookEntries ".github/hooks/hooks.json" "copilotHooksAgent" $manifest $manifestPath $TargetRepo
        Remove-OwnedFiles "copilotFiles" "opencodeFiles" $manifest $manifestPath $TargetRepo
        Remove-EmptyDirectory (Join-Path $TargetRepo ".github/hooks")
        Remove-EmptyDirectory (Join-Path $TargetRepo "hooks")
    }
    if ($selectedRuntime -in @("opencode", "both")) {
        Remove-OwnedFiles "opencodeFiles" "copilotFiles" $manifest $manifestPath $TargetRepo
        Remove-EmptyDirectory (Join-Path $TargetRepo ".opencode/plugins")
        Remove-EmptyDirectory (Join-Path $TargetRepo ".opencode")
        Remove-EmptyDirectory (Join-Path $TargetRepo "hooks")
    }
}

if ($PurgeData) {
    $dataPath = Join-Path $TargetRepo "observability"
    if (Test-Path -LiteralPath $dataPath) {
        if (Confirm-Removal "observability/") { Remove-Item -LiteralPath $dataPath -Recurse -Force }
    }
} elseif (Test-Path -LiteralPath (Join-Path $TargetRepo "observability")) {
    Write-Host "Observability data preserved. Use -PurgeData to remove it." -ForegroundColor Yellow
}

Write-Host "Uninstall complete for: $selectedRuntime" -ForegroundColor Cyan
