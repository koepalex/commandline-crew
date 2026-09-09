<#
.SYNOPSIS
    Uninstalls commandline-crew skills from Copilot CLI, OpenCode, or both.

.PARAMETER Runtime
    Target runtime: copilot, opencode, or both. Prompts when omitted.

.PARAMETER Force
    Removes repository-owned skill folders without prompting.
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
        $selection = (Read-Host "Uninstall skills from Copilot, OpenCode, or both? [copilot/opencode/both]").Trim().ToLowerInvariant()
        switch ($selection) {
            { $_ -in @("c", "copilot") } { return "copilot" }
            { $_ -in @("o", "opencode") } { return "opencode" }
            { $_ -in @("b", "both") } { return "both" }
            default { Write-Host "Please enter copilot, opencode, or both." -ForegroundColor Yellow }
        }
    }
}

function Get-UserHome {
    if ($env:USERPROFILE) { return $env:USERPROFILE }
    if ($env:HOME) { return $env:HOME }
    throw "Neither USERPROFILE nor HOME is set."
}

function Get-OpenCodeRoot {
    $configHome = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path (Get-UserHome) ".config" }
    return Join-Path $configHome "opencode"
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

function Get-TreeSha256 {
    param([string]$Path)
    $root = (Resolve-Path -LiteralPath $Path).Path
    $stream = New-Object IO.MemoryStream
    try {
        [string[]]$relativePaths = @(
            Get-ChildItem -LiteralPath $root -File -Recurse -Force |
                Where-Object {
                    $relative = $_.FullName.Substring($root.Length).TrimStart(
                        [IO.Path]::DirectorySeparatorChar,
                        [IO.Path]::AltDirectorySeparatorChar
                    )
                    $parts = $relative -split '[/\\]'
                    -not ($parts -contains "bin" -or $parts -contains "obj")
                } |
                ForEach-Object {
                    $_.FullName.Substring($root.Length).TrimStart(
                        [IO.Path]::DirectorySeparatorChar,
                        [IO.Path]::AltDirectorySeparatorChar
                    ) -replace '\\', '/'
                }
        )
        [Array]::Sort($relativePaths, [StringComparer]::Ordinal)
        foreach ($relative in $relativePaths) {
            $relativeBytes = [Text.Encoding]::UTF8.GetBytes($relative)
            $stream.Write($relativeBytes, 0, $relativeBytes.Length)
            $stream.WriteByte(0)
            $nativeRelative = $relative.Replace('/', [IO.Path]::DirectorySeparatorChar)
            $content = [IO.File]::ReadAllBytes((Join-Path $root $nativeRelative))
            $stream.Write($content, 0, $content.Length)
            $stream.WriteByte(0)
        }
        $stream.Position = 0
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "").ToLowerInvariant()
        } finally {
            $sha.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
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

function Remove-SkillsFrom {
    param(
        [Parameter(Mandatory)][string]$TargetDirectory,
        [Parameter(Mandatory)][string]$RuntimeName
    )

    $manifestPath = Join-Path (Split-Path -Parent $TargetDirectory) "commandline-crew-manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        Write-Host "No $RuntimeName ownership manifest found; no skills will be removed." -ForegroundColor Yellow
        return
    }
    $manifest = Read-JsonObject $manifestPath
    foreach ($name in @("agents", "mcp", "skills")) {
        if (-not $manifest.PSObject.Properties[$name]) {
            $manifest | Add-Member -MemberType NoteProperty -Name $name -Value ([PSCustomObject]@{})
        } elseif ($manifest.$name -isnot [PSCustomObject]) {
            throw "Manifest category '$name' must be an object: $manifestPath"
        }
    }
    if (-not (Test-Path -LiteralPath $TargetDirectory -PathType Container)) {
        foreach ($property in @($manifest.skills.PSObject.Properties)) {
            $manifest.skills.PSObject.Properties.Remove($property.Name)
            Write-Host "  Skill missing; dropped ownership: $($property.Name)" -ForegroundColor Yellow
        }
        Save-Manifest $manifest $manifestPath
        return
    }
    $targets = @(
        foreach ($property in @($manifest.skills.PSObject.Properties)) {
            $name = $property.Name
            $targetPath = Join-Path $TargetDirectory $name
            if (
                (Test-Path -LiteralPath $targetPath -PathType Container) -and
                $property.Value.PSObject.Properties["treeSha256"] -and
                (Get-TreeSha256 $targetPath) -eq ([string]$property.Value.treeSha256).ToLowerInvariant()
            ) {
                [PSCustomObject]@{ Name = $name; Path = $targetPath }
            } else {
                Write-Host "  Preserved modified or missing skill and dropped ownership: $name" -ForegroundColor Yellow
                $manifest.skills.PSObject.Properties.Remove($name)
                Save-Manifest $manifest $manifestPath
            }
        }
    )
    if ($targets.Count -eq 0) {
        Write-Host "No commandline-crew skills found for $RuntimeName." -ForegroundColor Gray
        return
    }
    if (-not $Force) {
        $response = Read-Host "Remove $($targets.Count) commandline-crew skill(s) from $RuntimeName? [y/N]"
        if ($response -notmatch "^[Yy]") {
            Write-Host "  Skipped: $RuntimeName skills" -ForegroundColor Yellow
            return
        }
    }
    foreach ($target in $targets) {
        Remove-Item -LiteralPath $target.Path -Recurse -Force
        $manifest.skills.PSObject.Properties.Remove($target.Name)
        Save-Manifest $manifest $manifestPath
        Write-Host "  Removed: $($target.Name)" -ForegroundColor Green
    }
    if (@(Get-ChildItem -LiteralPath $TargetDirectory -Force).Count -eq 0) {
        Remove-Item -LiteralPath $TargetDirectory -Force
        Write-Host "  Removed empty skills directory" -ForegroundColor Gray
    }
}

$selectedRuntime = Resolve-Runtime

Write-Host "Commandline Crew - Skills Uninstaller ($selectedRuntime)" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

$userHome = Get-UserHome
if ($selectedRuntime -in @("copilot", "both")) {
    Remove-SkillsFrom `
        -TargetDirectory (Join-Path $userHome ".copilot/skills") `
        -RuntimeName "Copilot"
}
if ($selectedRuntime -in @("opencode", "both")) {
    Remove-SkillsFrom `
        -TargetDirectory (Join-Path (Get-OpenCodeRoot) "skills") `
        -RuntimeName "OpenCode"
}

Write-Host ""
Write-Host "Uninstall complete for: $selectedRuntime" -ForegroundColor Cyan
