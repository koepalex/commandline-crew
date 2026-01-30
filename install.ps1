<#
.SYNOPSIS
    Installs commandline-crew agents and MCP config to user's Copilot CLI configuration.

.DESCRIPTION
    Copies agent files from this repository to C:\Users\<USER>\.copilot\agents\
    and merges MCP servers from .copilot\mcp-config.json into the user's 
    C:\Users\<USER>\.copilot\mcp-config.json, preserving existing custom servers.

.PARAMETER Force
    Overwrites existing files without prompting.

.EXAMPLE
    .\install.ps1
    .\install.ps1 -Force
#>

param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Paths
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceAgentsDir = Join-Path $scriptDir ".github\agents"
$sourceMcpConfig = Join-Path $scriptDir ".copilot\mcp-config.json"
$targetCopilotDir = Join-Path $env:USERPROFILE ".copilot"
$targetAgentsDir = Join-Path $targetCopilotDir "agents"
$targetMcpConfig = Join-Path $targetCopilotDir "mcp-config.json"

Write-Host "Commandline Crew - Installer" -ForegroundColor Cyan
Write-Host "============================" -ForegroundColor Cyan
Write-Host ""

# Create .copilot directory if needed
if (-not (Test-Path $targetCopilotDir)) {
    Write-Host "Creating .copilot directory: $targetCopilotDir" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $targetCopilotDir -Force | Out-Null
}

# --- MCP Config Installation ---
if (Test-Path $sourceMcpConfig) {
    Write-Host "MCP Configuration" -ForegroundColor Cyan
    Write-Host "-----------------" -ForegroundColor Cyan
    
    try {
        # Load source MCP config
        $sourceConfig = Get-Content $sourceMcpConfig -Raw | ConvertFrom-Json
        
        if (Test-Path $targetMcpConfig) {
            # Load existing user MCP config
            $targetConfig = Get-Content $targetMcpConfig -Raw | ConvertFrom-Json
            
            # Ensure mcpServers property exists
            if (-not $targetConfig.PSObject.Properties['mcpServers']) {
                $targetConfig | Add-Member -MemberType NoteProperty -Name 'mcpServers' -Value ([PSCustomObject]@{})
            }
            
            # Merge servers from source into target
            $merged = 0
            $skipped = 0
            foreach ($serverName in $sourceConfig.mcpServers.PSObject.Properties.Name) {
                if ($targetConfig.mcpServers.PSObject.Properties[$serverName]) {
                    Write-Host "  Server '$serverName' already exists in user config" -ForegroundColor Yellow
                    if (-not $Force) {
                        $response = Read-Host "  Overwrite '$serverName'? [y/N]"
                        if ($response -notmatch "^[Yy]") {
                            Write-Host "  Skipped: $serverName" -ForegroundColor Yellow
                            $skipped++
                            continue
                        }
                    }
                    # Remove existing server to replace it
                    $targetConfig.mcpServers.PSObject.Properties.Remove($serverName)
                }
                
                # Add/update server
                $targetConfig.mcpServers | Add-Member -MemberType NoteProperty -Name $serverName -Value $sourceConfig.mcpServers.$serverName -Force
                Write-Host "  Merged: $serverName" -ForegroundColor Green
                $merged++
            }
            
            # Save merged config
            $targetConfig | ConvertTo-Json -Depth 10 | Set-Content $targetMcpConfig -Encoding UTF8
            Write-Host "  Total merged: $merged server(s)" -ForegroundColor Green
            if ($skipped -gt 0) {
                Write-Host "  Total skipped: $skipped server(s)" -ForegroundColor Yellow
            }
        } else {
            # No existing config, just copy the source
            Copy-Item -Path $sourceMcpConfig -Destination $targetMcpConfig -Force
            Write-Host "  Installed: mcp-config.json (new)" -ForegroundColor Green
        }
    } catch {
        Write-Host "  ERROR: Failed to merge MCP config: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Skipped: mcp-config.json" -ForegroundColor Yellow
    }
    Write-Host ""
}

# --- Agents Installation ---
Write-Host "Agents" -ForegroundColor Cyan
Write-Host "------" -ForegroundColor Cyan

# Check source exists
if (-not (Test-Path $sourceAgentsDir)) {
    Write-Host "ERROR: Source agents directory not found: $sourceAgentsDir" -ForegroundColor Red
    exit 1
}

# Create target directory if needed
if (-not (Test-Path $targetAgentsDir)) {
    Write-Host "Creating agents directory: $targetAgentsDir" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $targetAgentsDir -Force | Out-Null
}

# Get agent files
$agentFiles = Get-ChildItem -Path $sourceAgentsDir -Filter "*.agent.md"

if ($agentFiles.Count -eq 0) {
    Write-Host "WARNING: No agent files (*.agent.md) found in $sourceAgentsDir" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($agentFiles.Count) agent(s) to install:" -ForegroundColor Green
$agentFiles | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
Write-Host ""

# Copy each agent file
$installed = 0
$skipped = 0

foreach ($file in $agentFiles) {
    $targetPath = Join-Path $targetAgentsDir $file.Name
    $exists = Test-Path $targetPath
    
    if ($exists -and -not $Force) {
        $response = Read-Host "Agent '$($file.Name)' already exists. Overwrite? [y/N]"
        if ($response -notmatch "^[Yy]") {
            Write-Host "  Skipped: $($file.Name)" -ForegroundColor Yellow
            $skipped++
            continue
        }
    }
    
    Copy-Item -Path $file.FullName -Destination $targetPath -Force
    Write-Host "  Installed: $($file.Name)" -ForegroundColor Green
    $installed++
}

Write-Host ""
Write-Host "Installation complete!" -ForegroundColor Cyan
Write-Host "  Installed: $installed agent(s)" -ForegroundColor Green
if ($skipped -gt 0) {
    Write-Host "  Skipped:   $skipped agent(s)" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "Agents are now available globally. Use them with:" -ForegroundColor Gray
Write-Host "  copilot --agent <agent-name> -p ""your prompt""" -ForegroundColor White
Write-Host ""
Write-Host "Available agents:" -ForegroundColor Gray
$agentFiles | ForEach-Object { 
    $name = $_.BaseName -replace "\.agent$", ""
    Write-Host "  @$name" -ForegroundColor White 
}
