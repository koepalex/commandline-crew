<#
.SYNOPSIS
    Installs hooks observability for Copilot, OpenCode, or both.
#>

param(
    [Parameter(Mandatory)]
    [string]$TargetRepo,
    [ValidateSet("copilot", "opencode", "both")]
    [string]$Runtime,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Resolve-Runtime {
    if ($Runtime) { return $Runtime.ToLowerInvariant() }
    while ($true) {
        $value = (Read-Host "Install hooks for Copilot, OpenCode, or both? [copilot/opencode/both]").Trim().ToLowerInvariant()
        if ($value -in @("c", "copilot")) { return "copilot" }
        if ($value -in @("o", "opencode")) { return "opencode" }
        if ($value -in @("b", "both")) { return "both" }
        Write-Host "Please enter copilot, opencode, or both." -ForegroundColor Yellow
    }
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
    if (Test-Path -LiteralPath $Path) {
        $manifest = Read-JsonObject $Path
    } else {
        $manifest = [PSCustomObject]@{
            version = 1
            copilotFiles = [PSCustomObject]@{}
            opencodeFiles = [PSCustomObject]@{}
            copilotHooksRoot = [PSCustomObject]@{}
            copilotHooksAgent = [PSCustomObject]@{}
            createdConfigs = [PSCustomObject]@{}
        }
    }
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
    Write-JsonSafely $Manifest $Path
    foreach ($categoryName in @(
        "copilotFiles", "opencodeFiles", "copilotHooksRoot", "copilotHooksAgent", "createdConfigs"
    )) {
        if (-not $Manifest.PSObject.Properties[$categoryName]) {
            $Manifest | Add-Member -MemberType NoteProperty -Name $categoryName -Value ([PSCustomObject]@{})
        }
    }
}

function Add-FileOwnership {
    param($Manifest, [string]$Category, [string]$RelativePath, [string]$TargetPath, [string]$ManifestPath)
    if ($Manifest.$Category.PSObject.Properties[$RelativePath]) {
        $Manifest.$Category.PSObject.Properties.Remove($RelativePath)
    }
    $record = [PSCustomObject]@{
        sha256 = (Get-FileHash -LiteralPath $TargetPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $Manifest.$Category | Add-Member -MemberType NoteProperty -Name $RelativePath -Value $record
    Save-Manifest $Manifest $ManifestPath
}

function Copy-OwnedFile {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$RelativePath,
        [string]$Category,
        $Manifest,
        [string]$ManifestPath
    )
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "Required source file not found: $Source" }
    $otherOwnedCategories = @(
        foreach ($candidate in @("copilotFiles", "opencodeFiles")) {
            if (
                $candidate -ne $Category -and
                $Manifest.$candidate.PSObject.Properties[$RelativePath]
            ) {
                $candidate
            }
        }
    )
    if (Test-Path -LiteralPath $Destination) {
        $contentMatches = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash -eq
            (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
        $ownedByCrew = $null -ne $Manifest.copilotFiles.PSObject.Properties[$RelativePath] -or
            $null -ne $Manifest.opencodeFiles.PSObject.Properties[$RelativePath]
        if ($contentMatches -and $ownedByCrew) {
            Add-FileOwnership $Manifest $Category $RelativePath $Destination $ManifestPath
            foreach ($otherCategory in $otherOwnedCategories) {
                Add-FileOwnership $Manifest $otherCategory $RelativePath $Destination $ManifestPath
            }
            Write-Host "  Registered shared ownership: $RelativePath" -ForegroundColor Gray
            return
        }
        if (-not $Force) {
            if ((Read-Host "  '$RelativePath' already exists. Overwrite? [y/N]") -notmatch "^[Yy]") {
                Write-Host "  Skipped: $RelativePath" -ForegroundColor Yellow
                return
            }
        }
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    Add-FileOwnership $Manifest $Category $RelativePath $Destination $ManifestPath
    foreach ($otherCategory in $otherOwnedCategories) {
        Add-FileOwnership $Manifest $otherCategory $RelativePath $Destination $ManifestPath
    }
    Write-Host "  Installed: $RelativePath" -ForegroundColor Green
}

function Get-OpenCodePluginFiles {
    param([string]$Directory)
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        throw "OpenCode plugin source directory not found: $Directory"
    }
    $files = @(Get-ChildItem -LiteralPath $Directory -File -Recurse)
    if ($files.Count -eq 0) { throw "No OpenCode plugin files found in: $Directory" }
    return $files
}

function Get-OpenCodePythonNames {
    param([array]$PluginFiles, [string]$HooksDirectory)
    $names = @("db.py")
    foreach ($file in $PluginFiles) {
        $names += @(
            [regex]::Matches((Get-Content -LiteralPath $file.FullName -Raw), '[A-Za-z0-9_.-]+\.py') |
                ForEach-Object { $_.Value }
        )
    }
    if (Test-Path -LiteralPath (Join-Path $HooksDirectory "opencode_bridge.py")) { $names += "opencode_bridge.py" }
    return @($names | Sort-Object -Unique)
}

function Test-ManifestHookEntry {
    param($Manifest, [string]$Category, [string]$Event, $Value)
    $eventProperty = $Manifest.$Category.PSObject.Properties[$Event]
    if (-not $eventProperty) { return $false }
    foreach ($entry in @($eventProperty.Value)) {
        if (Test-JsonEqual $entry $Value) {
            return $true
        }
    }
    return $false
}

function Merge-HooksConfig {
    param(
        [string]$SourcePath,
        [string]$TargetPath,
        [string]$RelativePath,
        [string]$Category,
        $Manifest,
        [string]$ManifestPath
    )
    $source = Read-JsonObject $SourcePath
    if ($source.hooks -isnot [PSCustomObject]) { throw "'hooks' must be an object in $SourcePath" }
    $created = -not (Test-Path -LiteralPath $TargetPath)
    $target = if ($created) { [PSCustomObject]@{} } else { Read-JsonObject $TargetPath }
    if (-not $target.PSObject.Properties["hooks"]) {
        $target | Add-Member -MemberType NoteProperty -Name "hooks" -Value ([PSCustomObject]@{})
    } elseif ($target.hooks -isnot [PSCustomObject]) {
        throw "'hooks' must be an object in $TargetPath"
    }

    $installed = @()
    foreach ($eventProperty in $source.hooks.PSObject.Properties) {
        $event = $eventProperty.Name
        $sourceHooks = @($eventProperty.Value)
        if (-not $target.hooks.PSObject.Properties[$event]) {
            $target.hooks | Add-Member -MemberType NoteProperty -Name $event -Value @()
        } elseif ($target.hooks.$event -isnot [array]) {
            throw "Hook event '$event' must be an array in $TargetPath"
        }
        foreach ($hook in $sourceHooks) {
            $alreadyPresent = $false
            foreach ($existing in @($target.hooks.$event)) {
                if (Test-JsonEqual $existing $hook) { $alreadyPresent = $true; break }
            }
            if ($alreadyPresent) {
                if (-not (Test-ManifestHookEntry $Manifest $Category $event $hook)) {
                    Write-Host "  Preserved pre-existing hook: $RelativePath [$event]" -ForegroundColor Yellow
                }
                continue
            }
            $target.hooks.$event = @($target.hooks.$event) + $hook
            $installed += [PSCustomObject]@{ event = $event; value = $hook }
        }
    }
    if ($installed.Count -eq 0) { return }
    Write-JsonSafely $target $TargetPath
    if ($created -and -not $Manifest.createdConfigs.PSObject.Properties[$RelativePath]) {
        $Manifest.createdConfigs | Add-Member -MemberType NoteProperty -Name $RelativePath -Value $true
    }
    foreach ($entry in $installed) {
        if (-not $Manifest.$Category.PSObject.Properties[$entry.event]) {
            $Manifest.$Category | Add-Member -MemberType NoteProperty -Name $entry.event -Value @()
        }
        $Manifest.$Category.$($entry.event) = @($Manifest.$Category.$($entry.event)) + $entry.value
    }
    Save-Manifest $Manifest $ManifestPath
    Write-Host "  Merged $($installed.Count) hook(s): $RelativePath" -ForegroundColor Green
}

$selectedRuntime = Resolve-Runtime
if (-not (Test-Path -LiteralPath $TargetRepo -PathType Container)) { throw "Target repository not found: $TargetRepo" }
$TargetRepo = (Resolve-Path -LiteralPath $TargetRepo).Path
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceHooks = Join-Path $scriptDir "hooks"
$sourcePluginDirectory = Join-Path $scriptDir ".opencode/plugins"
$manifestPath = Join-Path $TargetRepo ".commandline-crew/manifest.json"
$manifest = Get-Manifest $manifestPath

$copilotNames = @(
    "db.py", "session_start.py", "session_end.py", "user_prompt.py",
    "pre_tool_use.py", "post_tool_use.py", "error_occurred.py", "report.py"
)
$pluginFiles = @()
$openCodeNames = @()
if ($selectedRuntime -in @("opencode", "both")) {
    $pluginFiles = @(Get-OpenCodePluginFiles $sourcePluginDirectory)
    $openCodeNames = @(Get-OpenCodePythonNames $pluginFiles $sourceHooks)
}

Write-Host "Hooks Observability - Installer ($selectedRuntime)" -ForegroundColor Cyan

if ($selectedRuntime -in @("copilot", "both")) {
    foreach ($name in $copilotNames) {
        Copy-OwnedFile `
            -Source (Join-Path $sourceHooks $name) `
            -Destination (Join-Path $TargetRepo "hooks/$name") `
            -RelativePath "hooks/$name" `
            -Category "copilotFiles" `
            -Manifest $manifest `
            -ManifestPath $manifestPath
    }
    Merge-HooksConfig `
        -SourcePath (Join-Path $scriptDir "hooks.json") `
        -TargetPath (Join-Path $TargetRepo "hooks.json") `
        -RelativePath "hooks.json" `
        -Category "copilotHooksRoot" `
        -Manifest $manifest `
        -ManifestPath $manifestPath
    Merge-HooksConfig `
        -SourcePath (Join-Path $scriptDir "hooks.json") `
        -TargetPath (Join-Path $TargetRepo ".github/hooks/hooks.json") `
        -RelativePath ".github/hooks/hooks.json" `
        -Category "copilotHooksAgent" `
        -Manifest $manifest `
        -ManifestPath $manifestPath
}

if ($selectedRuntime -in @("opencode", "both")) {
    foreach ($name in $openCodeNames) {
        Copy-OwnedFile `
            -Source (Join-Path $sourceHooks $name) `
            -Destination (Join-Path $TargetRepo "hooks/$name") `
            -RelativePath "hooks/$name" `
            -Category "opencodeFiles" `
            -Manifest $manifest `
            -ManifestPath $manifestPath
    }
    foreach ($file in $pluginFiles) {
        $relative = $file.FullName.Substring($sourcePluginDirectory.Length).TrimStart(
            [IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar
        ) -replace '\\', '/'
        $targetRelative = ".opencode/plugins/$relative"
        Copy-OwnedFile `
            -Source $file.FullName `
            -Destination (Join-Path $TargetRepo $targetRelative) `
            -RelativePath $targetRelative `
            -Category "opencodeFiles" `
            -Manifest $manifest `
            -ManifestPath $manifestPath
    }
}

Write-Host "Installation complete for: $selectedRuntime" -ForegroundColor Cyan
