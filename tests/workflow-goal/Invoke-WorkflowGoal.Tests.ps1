[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "..\..")
)
$helperPath = Join-Path $repositoryRoot "skills\workflow-goal\Invoke-WorkflowGoal.ps1"
$testRoot = Join-Path (
    [IO.Path]::GetTempPath()
) "workflow-goal-tests-$([Guid]::NewGuid().ToString('N'))"
$artifactRoot = Join-Path $testRoot "artifacts"
$configPath = Join-Path $testRoot "config.json"
$fakeCopilotPath = Join-Path $testRoot "FakeCopilot.ps1"
$powerShellExecutable = (Get-Command pwsh -ErrorAction Stop).Source
$statePath = Join-Path $testRoot "concurrency.txt"
$argumentLogPath = Join-Path $testRoot "arguments"

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
}

function Assert-Equal {
    param(
        [object]$Expected,
        [object]$Actual,
        [string]$Message
    )

    if ($Expected -ne $Actual) {
        throw "Assertion failed: $Message. Expected '$Expected', got '$Actual'."
    }
}

function Reset-FakeState {
    Set-Content -LiteralPath $statePath -Value "0,0" -NoNewline
    if (Test-Path -LiteralPath $argumentLogPath) {
        Remove-Item -LiteralPath $argumentLogPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $argumentLogPath -Force | Out-Null
}

function Get-MaxObservedConcurrency {
    $parts = (Get-Content -LiteralPath $statePath -Raw).Split(",")
    return [int]$parts[1]
}

function New-TaskManifest {
    param(
        [string]$Name,
        [int]$Count,
        [int]$Workers,
        [string]$Model,
        [string[]]$Modes = @()
    )

    $tasks = for ($index = 0; $index -lt $Count; $index++) {
        $mode = if ($index -lt $Modes.Count) { $Modes[$index] } else { "" }
        [ordered]@{
            id     = "task-$('{0:d3}' -f $index)"
            title  = "Task $index"
            prompt = "Inspect item $index. $mode"
        }
    }

    $manifest = [ordered]@{
        runId      = $Name
        goal       = "Complete the mocked workflow."
        repository = $repositoryRoot
        settings   = [ordered]@{
            workers = $Workers
            model   = $Model
            context = "default"
        }
        tasks      = @($tasks)
    }

    $path = Join-Path $testRoot "$Name.json"
    $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path
    return $path
}

function Invoke-Launcher {
    param(
        [string]$ManifestPath,
        [hashtable]$AdditionalParameters = @{}
    )

    $parameters = @{
        Mode                   = "Run"
        TasksFile              = $ManifestPath
        ConfigPath             = $configPath
        CopilotExecutable      = $powerShellExecutable
        CopilotPrefixArguments = @("-NoProfile", "-File", $fakeCopilotPath)
    }
    foreach ($key in $AdditionalParameters.Keys) {
        $parameters[$key] = $AdditionalParameters[$key]
    }

    $output = & $helperPath @parameters
    return $output | ConvertFrom-Json
}

function Get-DecodedArguments {
    $logFile = Get-ChildItem -LiteralPath $argumentLogPath -Filter "*.args" |
        Select-Object -First 1
    Assert-True ($null -ne $logFile) "A worker argument log should exist"

    return @(
        Get-Content -LiteralPath $logFile.FullName |
            ForEach-Object {
                [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_))
            }
    )
}

New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
New-Item -ItemType Directory -Path $argumentLogPath -Force | Out-Null

$fakeCopilotSource = @'
$ErrorActionPreference = "Stop"
$RemainingArguments = @($args)
$statePath = $env:WORKFLOW_GOAL_FAKE_STATE
$runId = if ($env:WORKFLOW_GOAL_FAKE_RUN_ID) {
    $env:WORKFLOW_GOAL_FAKE_RUN_ID
} else {
    "default"
}
$mutex = [Threading.Mutex]::new($false, "workflow_goal_test_$runId")

function Update-Concurrency {
    param([int]$Delta)

    [void]$mutex.WaitOne()
    try {
        $values = if (Test-Path -LiteralPath $statePath) {
            (Get-Content -LiteralPath $statePath -Raw).Split(",")
        } else {
            @("0", "0")
        }
        $active = [int]$values[0] + $Delta
        $maximum = [Math]::Max([int]$values[1], $active)
        Set-Content -LiteralPath $statePath -Value "$active,$maximum" -NoNewline
    } finally {
        $mutex.ReleaseMutex()
    }
}

$encodedArguments = $RemainingArguments | ForEach-Object {
    [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($_))
}
$argumentPath = Join-Path $env:WORKFLOW_GOAL_FAKE_ARGUMENTS "$PID.args"
[IO.File]::WriteAllLines($argumentPath, $encodedArguments)

$prompt = ""
$model = ""
for ($index = 0; $index -lt $RemainingArguments.Count - 1; $index++) {
    if ($RemainingArguments[$index] -eq "-p") {
        $prompt = $RemainingArguments[$index + 1]
    }
    if ($RemainingArguments[$index] -eq "--model") {
        $model = $RemainingArguments[$index + 1]
    }
}

Update-Concurrency 1
try {
    if ($prompt -match "\[SLEEP:(\d+)\]") {
        Start-Sleep -Milliseconds ([int]$Matches[1])
    }
    if ($prompt.Contains("[MODE:FAIL]")) {
        [Console]::Error.WriteLine("requested failure")
        exit 7
    }
    if ($prompt.Contains("[MODE:EMPTY]")) {
        exit 0
    }

    @"
## Findings
- Fake result using model $model.

## Evidence
- FakeCopilot process $PID.

## Risks and unknowns
- None.

## Recommended parent action
- Continue the mocked workflow.
"@
} finally {
    Update-Concurrency -1
    $mutex.Dispose()
}
'@

Set-Content -LiteralPath $fakeCopilotPath -Value $fakeCopilotSource

$config = [ordered]@{
    defaultWorkers           = 2
    workerModel              = "claude-haiku-4.5"
    workerContext            = "default"
    workerTimeoutSeconds     = 30
    workerMaxAiCredits       = $null
    hardWorkerLimit          = $null
    artifactRoot             = $artifactRoot
    retainArtifactsOnSuccess = $false
    allowAllUrls             = $true
    readOnlyMcpServers       = @("context7")
    readOnlyMcpTools         = @(
        [ordered]@{
            server = "github-mcp-server"
            tools  = @("search_code")
        }
    )
    disabledMcpServers       = @("playwright")
}
$config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath

$originalEnvironment = @{
    State     = $env:WORKFLOW_GOAL_FAKE_STATE
    RunId     = $env:WORKFLOW_GOAL_FAKE_RUN_ID
    Arguments = $env:WORKFLOW_GOAL_FAKE_ARGUMENTS
    Workers   = $env:WORKFLOW_GOAL_WORKERS
}

try {
    $env:WORKFLOW_GOAL_FAKE_STATE = $statePath
    $env:WORKFLOW_GOAL_FAKE_ARGUMENTS = $argumentLogPath

    Reset-FakeState
    $env:WORKFLOW_GOAL_FAKE_RUN_ID = "override"
    $env:WORKFLOW_GOAL_WORKERS = "3"
    $overrideManifest = New-TaskManifest `
        -Name "prompt-overrides" `
        -Count 6 `
        -Workers 4 `
        -Model "gpt-5.5-mini" `
        -Modes @(
            "[SLEEP:300]",
            "[SLEEP:300]",
            "[SLEEP:300]",
            "[SLEEP:300]",
            "[SLEEP:300]",
            "[SLEEP:300]"
        )
    $overrideManifestObject = Get-Content -LiteralPath $overrideManifest -Raw |
        ConvertFrom-Json
    $overrideManifestObject.settings |
        Add-Member -NotePropertyName maxAiCredits -NotePropertyValue 2.5
    $overrideManifestObject |
        ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $overrideManifest
    $overrideResult = Invoke-Launcher `
        -ManifestPath $overrideManifest `
        -AdditionalParameters @{
            Workers = 5
            WorkerModel = "gpt-5.4-mini"
        }

    $overrideError = if ($overrideResult.results.Count -gt 0 -and
        (Test-Path -LiteralPath $overrideResult.results[0].stderrPath)) {
        Get-Content -LiteralPath $overrideResult.results[0].stderrPath -Raw
    } else {
        ""
    }
    Assert-Equal "succeeded" $overrideResult.status (
        "Override run should succeed: $overrideError; $($overrideResult | ConvertTo-Json -Depth 8 -Compress)"
    )
    Assert-Equal 4 $overrideResult.workers "Manifest worker count should win"
    Assert-Equal "gpt-5.5-mini" $overrideResult.model "Manifest model should pass through exactly"
    Assert-Equal 6 $overrideResult.succeeded "Every override task should succeed"
    Assert-Equal 6 $overrideResult.succeededTaskKeys.Count "Successful task keys should be emitted"
    Assert-True (
        $overrideResult.results[0].taskKey -match "^[0-9a-f]{64}$"
    ) "Every task should receive a canonical SHA-256 key"
    Assert-True ((Get-MaxObservedConcurrency) -ge 2) "Workers should overlap"

    $arguments = Get-DecodedArguments
    $modelIndex = [Array]::IndexOf($arguments, "--model")
    Assert-True ($modelIndex -ge 0) "Model argument should be present"
    Assert-Equal "gpt-5.5-mini" $arguments[$modelIndex + 1] "Exact model should reach Copilot"
    Assert-True (
        $arguments -contains "--deny-tool=shell,write,memory"
    ) "Destructive tool kinds should be denied"
    Assert-True (
        $arguments -contains "--excluded-tools=task,ask_user"
    ) "Subagent and user-interaction tools should be excluded"
    Assert-True (
        $arguments -contains "--allow-tool=read,context7,github-mcp-server(search_code)"
    ) "Read and configured MCP tools should be allowlisted"
    Assert-True (
        $arguments -contains "--disable-mcp-server"
    ) "Disabled MCP server arguments should be present"
    $creditIndex = [Array]::IndexOf($arguments, "--max-ai-credits")
    Assert-True ($creditIndex -ge 0) "AI credit limit argument should be present"
    Assert-Equal "2.5" $arguments[$creditIndex + 1] "AI credit limit should use invariant formatting"

    & $helperPath `
        -Mode Cleanup `
        -RunDirectory $overrideResult.runDirectory `
        -ConfigPath $configPath | Out-Null
    Assert-True (
        -not (Test-Path -LiteralPath $overrideResult.runDirectory)
    ) "Cleanup should remove a completed run"

    Reset-FakeState
    $env:WORKFLOW_GOAL_FAKE_RUN_ID = "forty-one"
    $fortyOneModes = @(1..41 | ForEach-Object { "[SLEEP:5000]" })
    $fortyOneManifest = New-TaskManifest `
        -Name "forty-one-workers" `
        -Count 41 `
        -Workers 41 `
        -Model "claude-haiku-4.5" `
        -Modes $fortyOneModes
    $fortyOneResult = Invoke-Launcher -ManifestPath $fortyOneManifest

    Assert-Equal 41 $fortyOneResult.workers "One-per-file request should use 41 workers"
    Assert-Equal 41 $fortyOneResult.succeeded "All 41 workers should finish"
    Assert-Equal 41 (
        Get-ChildItem -LiteralPath $argumentLogPath -Filter "*.args"
    ).Count "The launcher should start 41 worker processes"
    Assert-True (
        (Get-MaxObservedConcurrency) -ge 30
    ) "At least 30 of 41 workers should overlap in the mocked run"

    Reset-FakeState
    $env:WORKFLOW_GOAL_FAKE_RUN_ID = "cancel"
    $cancelManifest = New-TaskManifest `
        -Name "cancel-running-workers" `
        -Count 8 `
        -Workers 8 `
        -Model "claude-haiku-4.5" `
        -Modes @(1..8 | ForEach-Object { "[SLEEP:10000]" })
    $cancelRunDirectory = Join-Path $artifactRoot "cancel-running-workers"
    $cancelJob = Start-Job -ScriptBlock {
        param(
            $HelperPath,
            $ManifestPath,
            $ConfigurationPath,
            $Executable,
            $PrefixArguments,
            $FakeState,
            $FakeArguments
        )

        $env:WORKFLOW_GOAL_FAKE_STATE = $FakeState
        $env:WORKFLOW_GOAL_FAKE_RUN_ID = "cancel"
        $env:WORKFLOW_GOAL_FAKE_ARGUMENTS = $FakeArguments
        & $HelperPath `
            -Mode Run `
            -TasksFile $ManifestPath `
            -ConfigPath $ConfigurationPath `
            -CopilotExecutable $Executable `
            -CopilotPrefixArguments $PrefixArguments
    } -ArgumentList @(
        $helperPath,
        $cancelManifest,
        $configPath,
        $powerShellExecutable,
        @("-NoProfile", "-File", $fakeCopilotPath),
        $statePath,
        $argumentLogPath
    )

    $cancelRunManifest = Join-Path $cancelRunDirectory "run-manifest.json"
    for ($attempt = 0; $attempt -lt 100 -and
        -not (Test-Path -LiteralPath $cancelRunManifest);
        $attempt++) {
        Start-Sleep -Milliseconds 100
    }
    Assert-True (
        Test-Path -LiteralPath $cancelRunManifest
    ) "A running helper should publish its manifest"

    $cancelResultJson = & $helperPath `
        -Mode Cancel `
        -RunDirectory $cancelRunDirectory `
        -ConfigPath $configPath
    $cancelResult = $cancelResultJson | ConvertFrom-Json
    Assert-Equal "cancelled" $cancelResult.status "Cancel mode should stop the run"

    Wait-Job -Job $cancelJob -Timeout 60 | Out-Null
    Assert-Equal "Completed" $cancelJob.State "Cancelled helper should exit"
    $cancelRunResult = Receive-Job -Job $cancelJob | ConvertFrom-Json
    Assert-Equal "cancelled" $cancelRunResult.status "Run summary should report cancellation"
    Assert-True (
        $cancelRunResult.cancelled -gt 0
    ) "Cancelled tasks should be counted"
    Remove-Job -Job $cancelJob -Force

    & $helperPath `
        -Mode Cleanup `
        -RunDirectory $cancelRunDirectory `
        -ConfigPath $configPath | Out-Null

    Reset-FakeState
    $env:WORKFLOW_GOAL_FAKE_RUN_ID = "partial"
    $partialManifest = New-TaskManifest `
        -Name "partial-results" `
        -Count 4 `
        -Workers 4 `
        -Model "claude-haiku-4.5" `
        -Modes @(
            "",
            "[MODE:FAIL]",
            "[MODE:EMPTY]",
            "[SLEEP:5000]"
        )
    $partial = Get-Content -LiteralPath $partialManifest -Raw | ConvertFrom-Json
    $partial.settings | Add-Member -NotePropertyName timeoutSeconds -NotePropertyValue 3
    $partial | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $partialManifest
    $partialResult = Invoke-Launcher -ManifestPath $partialManifest

    Assert-Equal "partial" $partialResult.status "Mixed outcomes should be partial"
    Assert-Equal 1 $partialResult.succeeded "One worker should succeed"
    Assert-Equal 2 $partialResult.failed "Failure and empty output should fail"
    Assert-Equal 1 $partialResult.timedOut "One worker should time out"

    Reset-FakeState
    $env:WORKFLOW_GOAL_FAKE_RUN_ID = "round-two"
    $roundTwoManifest = New-TaskManifest `
        -Name "second-fan-out-round" `
        -Count 2 `
        -Workers 2 `
        -Model "claude-haiku-4.5"
    $roundTwoResult = Invoke-Launcher -ManifestPath $roundTwoManifest
    Assert-Equal "succeeded" $roundTwoResult.status "A later fan-out round should run independently"

    Reset-FakeState
    $env:WORKFLOW_GOAL_FAKE_RUN_ID = "round-two-copy"
    $roundTwoCopyManifest = New-TaskManifest `
        -Name "second-fan-out-round-copy" `
        -Count 2 `
        -Workers 2 `
        -Model "claude-haiku-4.5"
    $roundTwoCopyResult = Invoke-Launcher -ManifestPath $roundTwoCopyManifest
    Assert-Equal (
        $roundTwoResult.results[0].taskKey
    ) (
        $roundTwoCopyResult.results[0].taskKey
    ) "Unchanged task inputs should produce the same retry key"

    $limitedConfig = $config.PSObject.Copy()
    $limitedConfig.hardWorkerLimit = 3
    $limitedConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath
    $hardLimitManifest = New-TaskManifest `
        -Name "hard-limit" `
        -Count 4 `
        -Workers 4 `
        -Model "claude-haiku-4.5"

    $hardLimitFailed = $false
    try {
        Invoke-Launcher -ManifestPath $hardLimitManifest | Out-Null
    } catch {
        $hardLimitFailed = $_.Exception.Message -match "hardWorkerLimit"
    }
    Assert-True $hardLimitFailed "Configured hard limits should reject oversized fan-out"

    "All workflow-goal launcher tests passed."
} finally {
    $env:WORKFLOW_GOAL_FAKE_STATE = $originalEnvironment.State
    $env:WORKFLOW_GOAL_FAKE_RUN_ID = $originalEnvironment.RunId
    $env:WORKFLOW_GOAL_FAKE_ARGUMENTS = $originalEnvironment.Arguments
    $env:WORKFLOW_GOAL_WORKERS = $originalEnvironment.Workers

    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
