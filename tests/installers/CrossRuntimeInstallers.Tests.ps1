[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$testRoot = Join-Path (
    [IO.Path]::GetTempPath()
) "cross-runtime-installers-$([Guid]::NewGuid().ToString('N'))"
$profileRoot = Join-Path $testRoot "profile"
$xdgRoot = Join-Path $testRoot "xdg"
$targetRepo = Join-Path $testRoot "target-repo"
$originalUserProfile = $env:USERPROFILE
$originalHome = $env:HOME
$originalXdgConfigHome = $env:XDG_CONFIG_HOME

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
}

function Assert-JsonProperty {
    param(
        [string]$Path,
        [string]$MapName,
        [string]$PropertyName,
        [bool]$Expected
    )

    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $map = $config.PSObject.Properties[$MapName].Value
    $actual = $null -ne $map.PSObject.Properties[$PropertyName]
    Assert-True ($actual -eq $Expected) (
        "Expected '$MapName.$PropertyName' presence to be $Expected in $Path"
    )
}

try {
    New-Item -ItemType Directory -Path $profileRoot, $xdgRoot, $targetRepo -Force |
        Out-Null
    $env:USERPROFILE = $profileRoot
    $env:HOME = $profileRoot
    $env:XDG_CONFIG_HOME = $xdgRoot

    & (Join-Path $repositoryRoot "install-skills.ps1") `
        -Runtime both -Skill ask-folder -Force | Out-Null
    foreach ($skillPath in @(
        (Join-Path $profileRoot ".copilot\skills\ask-folder"),
        (Join-Path $xdgRoot "opencode\skills\ask-folder")
    )) {
        Assert-True (Test-Path -LiteralPath (Join-Path $skillPath "SKILL.md")) (
            "Skill entry point should be installed at $skillPath"
        )
        Assert-True (
            Test-Path -LiteralPath (
                Join-Path $skillPath "references\tools-and-safety.md"
            )
        ) "Nested skill references should be installed at $skillPath"
    }

    New-Item -ItemType Directory -Path (Join-Path $profileRoot ".copilot") -Force |
        Out-Null
    @{
        mcpServers = @{
            userServer = @{ type = "local"; command = "example" }
        }
    } | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath (Join-Path $profileRoot ".copilot\mcp-config.json")

    New-Item -ItemType Directory -Path (Join-Path $xdgRoot "opencode") -Force |
        Out-Null
    @{
        theme = "user-theme"
        mcp = @{
            userServer = @{ type = "local"; command = @("example") }
        }
    } | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath (Join-Path $xdgRoot "opencode\opencode.json")

    & (Join-Path $repositoryRoot "install.ps1") -Runtime both -Force | Out-Null
    Assert-True (
        Test-Path -LiteralPath (
            Join-Path $profileRoot ".copilot\agents\deep-thought.agent.md"
        )
    ) "Copilot agents should be installed"
    Assert-True (
        Test-Path -LiteralPath (
            Join-Path $xdgRoot "opencode\agents\deep-thought.md"
        )
    ) "OpenCode agent adapters should be installed"
    Assert-JsonProperty `
        -Path (Join-Path $profileRoot ".copilot\mcp-config.json") `
        -MapName mcpServers -PropertyName userServer -Expected $true
    Assert-JsonProperty `
        -Path (Join-Path $xdgRoot "opencode\opencode.json") `
        -MapName mcp -PropertyName userServer -Expected $true

    @{
        version = 1
        hooks = @{
            sessionStart = @(
                @{
                    type = "command"
                    bash = "python3 user-owned.py"
                }
            )
            userOwnedEvent = @(
                @{
                    type = "command"
                    bash = "python3 user-owned-event.py"
                }
            )
        }
    } | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath (Join-Path $targetRepo "hooks.json")

    & (Join-Path $repositoryRoot "install-hooks.ps1") `
        -TargetRepo $targetRepo -Runtime both -Force | Out-Null
    Assert-True (
        Test-Path -LiteralPath (Join-Path $targetRepo "hooks.json")
    ) "Copilot root hooks config should be installed"
    Assert-True (
        Test-Path -LiteralPath (
            Join-Path $targetRepo ".github\hooks\hooks.json"
        )
    ) "Copilot coding-agent hooks config should be installed"
    Assert-True (
        @(Get-ChildItem -LiteralPath (
            Join-Path $targetRepo ".opencode\plugins"
        ) -File -Recurse).Count -gt 0
    ) "OpenCode plugin should be installed"
    Assert-True (
        Test-Path -LiteralPath (Join-Path $targetRepo "hooks\opencode_bridge.py")
    ) "OpenCode Python bridge should be installed"
    $mergedHooks = Get-Content -LiteralPath (Join-Path $targetRepo "hooks.json") -Raw |
        ConvertFrom-Json
    Assert-True (
        @($mergedHooks.hooks.sessionStart |
            Where-Object { $_.bash -eq "python3 user-owned.py" }).Count -eq 1
    ) "Hook installation should preserve unrelated commands"

    Add-Content -LiteralPath (
        Join-Path $xdgRoot "opencode\agents\deep-thought.md"
    ) -Value "`nUser customization"
    $openCodeConfigPath = Join-Path $xdgRoot "opencode\opencode.json"
    $openCodeConfig = Get-Content -LiteralPath $openCodeConfigPath -Raw |
        ConvertFrom-Json
    $openCodeConfig.mcp.mslearn = [PSCustomObject]@{
        type = "remote"
        url = "https://user.example/mcp"
    }
    $openCodeConfig | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $openCodeConfigPath
    Add-Content -LiteralPath (
        Join-Path $profileRoot ".copilot\skills\ask-folder\SKILL.md"
    ) -Value "`nUser customization"

    & (Join-Path $repositoryRoot "uninstall-hooks.ps1") `
        -TargetRepo $targetRepo -Runtime opencode -Force | Out-Null
    Assert-True (
        Test-Path -LiteralPath (Join-Path $targetRepo "hooks.json")
    ) "Removing OpenCode hooks should preserve Copilot hooks"
    Assert-True (
        -not (Test-Path -LiteralPath (
            Join-Path $targetRepo ".opencode\plugins"
        ))
    ) "Repository-owned OpenCode plugin files should be removed"

    & (Join-Path $repositoryRoot "uninstall-hooks.ps1") `
        -TargetRepo $targetRepo -Runtime copilot -Force -PurgeData | Out-Null
    $remainingHooks = Get-Content -LiteralPath (Join-Path $targetRepo "hooks.json") -Raw |
        ConvertFrom-Json
    Assert-True (
        @($remainingHooks.hooks.sessionStart |
            Where-Object { $_.bash -eq "python3 user-owned.py" }).Count -eq 1
    ) "Hook uninstallation should preserve unrelated commands"
    Assert-True (
        $null -ne $remainingHooks.hooks.userOwnedEvent
    ) "Hook uninstallation should preserve unrelated events"

    & (Join-Path $repositoryRoot "uninstall-skills.ps1") `
        -Runtime both -Force | Out-Null
    & (Join-Path $repositoryRoot "uninstall.ps1") -Runtime both -Force | Out-Null

    Assert-JsonProperty `
        -Path (Join-Path $profileRoot ".copilot\mcp-config.json") `
        -MapName mcpServers -PropertyName userServer -Expected $true
    Assert-JsonProperty `
        -Path (Join-Path $xdgRoot "opencode\opencode.json") `
        -MapName mcp -PropertyName userServer -Expected $true
    Assert-True (
        Test-Path -LiteralPath (
            Join-Path $xdgRoot "opencode\agents\deep-thought.md"
        )
    ) "Modified OpenCode agents should be preserved"
    Assert-True (
        -not (Test-Path -LiteralPath (
            Join-Path $xdgRoot "opencode\agents\dotnet-bot.md"
        ))
    ) "Unchanged repository-owned OpenCode agents should be removed"
    Assert-JsonProperty `
        -Path (Join-Path $xdgRoot "opencode\opencode.json") `
        -MapName mcp -PropertyName mslearn -Expected $true
    Assert-True (
        Test-Path -LiteralPath (
            Join-Path $profileRoot ".copilot\skills\ask-folder\SKILL.md"
        )
    ) "Modified installed skills should be preserved"

    "All cross-runtime PowerShell installer tests passed."
} finally {
    $env:USERPROFILE = $originalUserProfile
    $env:HOME = $originalHome
    $env:XDG_CONFIG_HOME = $originalXdgConfigHome
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
