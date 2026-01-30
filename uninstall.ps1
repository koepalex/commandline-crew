<#
.SYNOPSIS
    Uninstalls commandline-crew agents and MCP config from user's Copilot CLI configuration.

.DESCRIPTION
    Removes agent files that were installed by install.ps1 from 
    C:\Users\<USER>\.copilot\agents\ and removes only the MCP servers 
    that were added by this repository, preserving other custom servers.

.PARAMETER Force
    Removes files without prompting for confirmation.

.EXAMPLE
    .\uninstall.ps1
    .\uninstall.ps1 -Force
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

Write-Host "Commandline Crew - Uninstaller" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan
Write-Host ""

# Check if agents directory exists
if (-not (Test-Path $targetAgentsDir)) {
    Write-Host "No agents directory found at: $targetAgentsDir" -ForegroundColor Yellow
}

# --- MCP Config Removal ---
if (Test-Path $targetMcpConfig) {
    Write-Host "MCP Configuration" -ForegroundColor Cyan
    Write-Host "-----------------" -ForegroundColor Cyan
    
    try {
        # Load configs to determine which servers to remove
        if (Test-Path $sourceMcpConfig) {
            $sourceConfig = Get-Content $sourceMcpConfig -Raw | ConvertFrom-Json
            $targetConfig = Get-Content $targetMcpConfig -Raw | ConvertFrom-Json
            
            # Find servers that came from this repo
            $serversToRemove = @()
            foreach ($serverName in $sourceConfig.mcpServers.PSObject.Properties.Name) {
                if ($targetConfig.mcpServers.PSObject.Properties[$serverName]) {
                    $serversToRemove += $serverName
                }
            }
            
            if ($serversToRemove.Count -eq 0) {
                Write-Host "  No commandline-crew MCP servers found to remove" -ForegroundColor Yellow
            } else {
                Write-Host "  Found $($serversToRemove.Count) server(s) to remove:" -ForegroundColor Yellow
                $serversToRemove | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
                
                $removeMcp = $Force
                if (-not $Force) {
                    $response = Read-Host "  Remove these MCP servers? [y/N]"
                    $removeMcp = $response -match "^[Yy]"
                }
                
                if ($removeMcp) {
                    # Remove servers
                    foreach ($serverName in $serversToRemove) {
                        $targetConfig.mcpServers.PSObject.Properties.Remove($serverName)
                        Write-Host "  Removed: $serverName" -ForegroundColor Green
                    }
                    
                    # Save updated config
                    $targetConfig | ConvertTo-Json -Depth 10 | Set-Content $targetMcpConfig -Encoding UTF8
                    Write-Host "  Total removed: $($serversToRemove.Count) server(s)" -ForegroundColor Green
                } else {
                    Write-Host "  Skipped: MCP server removal" -ForegroundColor Yellow
                }
            }
        } else {
            Write-Host "  WARNING: Cannot determine which servers to remove (source config not found)" -ForegroundColor Yellow
            $removeMcp = $Force
            if (-not $Force) {
                $response = Read-Host "  Remove entire MCP config file? [y/N]"
                $removeMcp = $response -match "^[Yy]"
            }
            
            if ($removeMcp) {
                Remove-Item -Path $targetMcpConfig -Force
                Write-Host "  Removed: mcp-config.json (entire file)" -ForegroundColor Green
            } else {
                Write-Host "  Skipped: mcp-config.json" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Host "  ERROR: Failed to process MCP config: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Skipped: MCP config removal" -ForegroundColor Yellow
    }
    Write-Host ""
}

# --- Agents Removal ---
Write-Host "Agents" -ForegroundColor Cyan
Write-Host "------" -ForegroundColor Cyan

if (-not (Test-Path $targetAgentsDir)) {
    Write-Host "Nothing to uninstall." -ForegroundColor Gray
    exit 0
}

# Get list of agents from source to know which ones to remove
$sourceAgentFiles = Get-ChildItem -Path $sourceAgentsDir -Filter "*.agent.md" -ErrorAction SilentlyContinue

if (-not $sourceAgentFiles -or $sourceAgentFiles.Count -eq 0) {
    Write-Host "WARNING: Cannot determine which agents to remove (source not found)." -ForegroundColor Yellow
    exit 1
}

# Find installed agents from this repo
$agentsToRemove = @()
foreach ($sourceFile in $sourceAgentFiles) {
    $targetPath = Join-Path $targetAgentsDir $sourceFile.Name
    if (Test-Path $targetPath) {
        $agentsToRemove += @{
            Name = $sourceFile.Name
            Path = $targetPath
        }
    }
}

if ($agentsToRemove.Count -eq 0) {
    Write-Host "No commandline-crew agents found to uninstall." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($agentsToRemove.Count) agent(s) to uninstall:" -ForegroundColor Yellow
$agentsToRemove | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
Write-Host ""

# Confirm removal
if (-not $Force) {
    $response = Read-Host "Are you sure you want to remove these agents? [y/N]"
    if ($response -notmatch "^[Yy]") {
        Write-Host "Uninstall cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Remove agents
$removed = 0
foreach ($agent in $agentsToRemove) {
    Remove-Item -Path $agent.Path -Force
    Write-Host "  Removed: $($agent.Name)" -ForegroundColor Green
    $removed++
}

Write-Host ""
Write-Host "Uninstall complete!" -ForegroundColor Cyan
Write-Host "  Removed: $removed agent(s)" -ForegroundColor Green

# Check if agents directory is empty and offer to remove it
$remainingFiles = Get-ChildItem -Path $targetAgentsDir -ErrorAction SilentlyContinue
if (-not $remainingFiles -or $remainingFiles.Count -eq 0) {
    if ($Force) {
        Remove-Item -Path $targetAgentsDir -Force
        Write-Host "  Removed empty agents directory" -ForegroundColor Gray
    } else {
        $response = Read-Host "Agents directory is now empty. Remove it? [y/N]"
        if ($response -match "^[Yy]") {
            Remove-Item -Path $targetAgentsDir -Force
            Write-Host "  Removed empty agents directory" -ForegroundColor Gray
        }
    }
}
