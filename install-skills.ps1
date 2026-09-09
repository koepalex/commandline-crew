<#
.SYNOPSIS
    Installs commandline-crew skills for Copilot CLI, OpenCode, or both.

.PARAMETER Runtime
    Target runtime: copilot, opencode, or both. Prompts when omitted.

.PARAMETER Skill
    Installs only the named skills. Accepts names or comma-separated names.

.PARAMETER Force
    Overwrites existing skill folders without prompting. When Skill is omitted,
    installs all available skills.
#>

param(
    [string[]]$Skill,

    [ValidateSet("copilot", "opencode", "both")]
    [string]$Runtime,

    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Resolve-Runtime {
    if ($Runtime) { return $Runtime.ToLowerInvariant() }
    while ($true) {
        $selection = (Read-Host "Install skills for Copilot, OpenCode, or both? [copilot/opencode/both]").Trim().ToLowerInvariant()
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

function Install-SkillsTo {
    param(
        [Parameter(Mandatory)][array]$SelectedSkills,
        [Parameter(Mandatory)][string]$TargetDirectory,
        [Parameter(Mandatory)][string]$RuntimeName
    )

    New-Item -ItemType Directory -Path $TargetDirectory -Force | Out-Null
    $runtimeRoot = Split-Path -Parent $TargetDirectory
    $manifestPath = Join-Path $runtimeRoot "commandline-crew-manifest.json"
    $manifest = Get-Manifest $manifestPath
    Write-Host "$RuntimeName skills: $TargetDirectory" -ForegroundColor Cyan

    foreach ($selectedSkill in $SelectedSkills) {
        $targetPath = Join-Path $TargetDirectory $selectedSkill.Name
        if (Test-Path -LiteralPath $targetPath) {
            if (-not $Force) {
                $response = Read-Host "  Skill '$($selectedSkill.Name)' already exists for $RuntimeName. Overwrite? [y/N]"
                if ($response -notmatch "^[Yy]") {
                    Write-Host "  Skipped: $($selectedSkill.Name)" -ForegroundColor Yellow
                    continue
                }
            }
            Remove-Item -LiteralPath $targetPath -Recurse -Force
        }

        Copy-Item -LiteralPath $selectedSkill.FullName -Destination $targetPath -Recurse -Force
        $generatedDirectories = @(
            Get-ChildItem -LiteralPath $targetPath -Directory -Recurse -Force |
                Where-Object { $_.Name -in @("bin", "obj") } |
                Sort-Object -Property FullName -Descending
        )
        foreach ($generatedDirectory in $generatedDirectories) {
            Remove-Item -LiteralPath $generatedDirectory.FullName -Recurse -Force
        }
        if ($manifest.skills.PSObject.Properties[$selectedSkill.Name]) {
            $manifest.skills.PSObject.Properties.Remove($selectedSkill.Name)
        }
        $manifest.skills | Add-Member -MemberType NoteProperty -Name $selectedSkill.Name -Value (
            [PSCustomObject]@{ treeSha256 = Get-TreeSha256 $targetPath }
        )
        foreach ($categoryName in @("agents", "mcp", "skills")) {
            if (
                $manifest.PSObject.Properties[$categoryName] -and
                @($manifest.$categoryName.PSObject.Properties).Count -eq 0
            ) {
                $manifest.PSObject.Properties.Remove($categoryName)
            }
        }
        Write-JsonSafely $manifest $manifestPath
        foreach ($categoryName in @("agents", "mcp", "skills")) {
            if (-not $manifest.PSObject.Properties[$categoryName]) {
                $manifest | Add-Member -MemberType NoteProperty -Name $categoryName -Value ([PSCustomObject]@{})
            }
        }
        Write-Host "  Installed: $($selectedSkill.Name)" -ForegroundColor Green
    }
    Write-Host ""
}

$selectedRuntime = Resolve-Runtime
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceSkillsDir = Join-Path $scriptDir "skills"

Write-Host "Commandline Crew - Skills Installer ($selectedRuntime)" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path -LiteralPath $sourceSkillsDir -PathType Container)) {
    throw "Source skills directory not found: $sourceSkillsDir"
}

$sourceSkills = @(Get-ChildItem -LiteralPath $sourceSkillsDir -Directory | Sort-Object Name)
$validSourceSkills = @(
    $sourceSkills | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "SKILL.md") -PathType Leaf }
)
if ($validSourceSkills.Count -eq 0) {
    throw "No valid skills containing SKILL.md found in $sourceSkillsDir"
}

$selectedSkills = @()
if ($Skill) {
    $requestedNames = @(
        $Skill |
            ForEach-Object { $_ -split "," } |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ } |
            Select-Object -Unique
    )
    $unknownNames = @($requestedNames | Where-Object { $_ -notin $validSourceSkills.Name })
    if ($unknownNames.Count -gt 0) {
        throw "Unknown skill(s): $($unknownNames -join ', '). Available skills: $($validSourceSkills.Name -join ', ')"
    }
    $selectedSkills = @($validSourceSkills | Where-Object { $_.Name -in $requestedNames })
} elseif ($Force) {
    $selectedSkills = $validSourceSkills
} else {
    Write-Host "Available skills:" -ForegroundColor Green
    for ($index = 0; $index -lt $validSourceSkills.Count; $index++) {
        Write-Host "  [$($index + 1)] $($validSourceSkills[$index].Name)" -ForegroundColor Gray
    }
    $response = Read-Host "Select skills by number or name (comma-separated), or enter 'all'"
    if ([string]::IsNullOrWhiteSpace($response)) {
        Write-Host "Installation cancelled." -ForegroundColor Yellow
        exit 0
    }

    $selections = @($response -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($selections -contains "all") {
        $selectedSkills = $validSourceSkills
    } else {
        $selectedNames = @()
        $invalidSelections = @()
        foreach ($selection in $selections) {
            if ($selection -match "^\d+$") {
                $selectedIndex = [int]$selection - 1
                if ($selectedIndex -ge 0 -and $selectedIndex -lt $validSourceSkills.Count) {
                    $selectedNames += $validSourceSkills[$selectedIndex].Name
                } else {
                    $invalidSelections += $selection
                }
            } elseif ($selection -in $validSourceSkills.Name) {
                $selectedNames += $selection
            } else {
                $invalidSelections += $selection
            }
        }
        if ($invalidSelections.Count -gt 0) {
            throw "Invalid selection(s): $($invalidSelections -join ', ')"
        }
        $selectedSkills = @($validSourceSkills | Where-Object { $_.Name -in $selectedNames })
    }
}

if ($selectedSkills.Count -eq 0) {
    Write-Host "No skills selected. Nothing to install." -ForegroundColor Yellow
    exit 0
}

$userHome = Get-UserHome
if ($selectedRuntime -in @("copilot", "both")) {
    Install-SkillsTo `
        -SelectedSkills $selectedSkills `
        -TargetDirectory (Join-Path $userHome ".copilot/skills") `
        -RuntimeName "Copilot"
}
if ($selectedRuntime -in @("opencode", "both")) {
    Install-SkillsTo `
        -SelectedSkills $selectedSkills `
        -TargetDirectory (Join-Path (Get-OpenCodeRoot) "skills") `
        -RuntimeName "OpenCode"
}

Write-Host "Installation complete for: $selectedRuntime" -ForegroundColor Cyan
