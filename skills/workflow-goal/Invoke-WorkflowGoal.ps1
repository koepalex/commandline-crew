[CmdletBinding()]
param(
    [ValidateSet("Run", "Cancel", "Cleanup")]
    [string]$Mode = "Run",

    [string]$TasksFile,

    [string]$ConfigPath = (Join-Path $PSScriptRoot "config.json"),

    [string]$RunDirectory,

    [Nullable[int]]$Workers,

    [string]$WorkerModel,

    [ValidateSet("default", "long_context")]
    [string]$WorkerContext,

    [Nullable[int]]$WorkerTimeoutSeconds,

    [Nullable[double]]$WorkerMaxAiCredits,

    [Nullable[int]]$HardWorkerLimit,

    [string]$CopilotExecutable = "copilot",

    [string[]]$CopilotPrefixArguments = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-Property {
    param(
        [object]$InputObject,
        [string]$Name
    )

    return $null -ne $InputObject -and
        $null -ne $InputObject.PSObject.Properties[$Name]
}

function Get-PropertyValue {
    param(
        [object]$InputObject,
        [string]$Name,
        [object]$DefaultValue = $null
    )

    if (Test-Property -InputObject $InputObject -Name $Name) {
        return $InputObject.PSObject.Properties[$Name].Value
    }

    return $DefaultValue
}

function ConvertTo-Boolean {
    param(
        [string]$Value,
        [string]$Name
    )

    switch -Regex ($Value) {
        "^(1|true|yes|on)$" { return $true }
        "^(0|false|no|off)$" { return $false }
        default { throw "$Name must be true or false." }
    }
}

function ConvertTo-PositiveInt {
    param(
        [object]$Value,
        [string]$Name
    )

    $parsed = 0
    if (-not [int]::TryParse([string]$Value, [ref]$parsed) -or $parsed -lt 1) {
        throw "$Name must be a positive integer."
    }

    return $parsed
}

function ConvertTo-OptionalPositiveDouble {
    param(
        [object]$Value,
        [string]$Name
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }

    $parsed = 0.0
    if (-not [double]::TryParse(
            [string]$Value,
            [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$parsed
        ) -or $parsed -le 0) {
        throw "$Name must be a positive number or null."
    }

    return $parsed
}

function Write-JsonAtomic {
    param(
        [string]$Path,
        [object]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 20
    $temporaryPath = "$Path.$PID.tmp"
    $utf8NoBom = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($temporaryPath, $json, $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Resolve-ArtifactRoot {
    param([object]$Settings)

    $configuredRoot = Get-PropertyValue -InputObject $Settings -Name "artifactRoot"
    if ([string]::IsNullOrWhiteSpace([string]$configuredRoot)) {
        $configuredRoot = Join-Path ([IO.Path]::GetTempPath()) "copilot-workflow-goal"
    }

    return [IO.Path]::GetFullPath(
        [Environment]::ExpandEnvironmentVariables([string]$configuredRoot)
    )
}

function Assert-ChildPath {
    param(
        [string]$Root,
        [string]$Candidate
    )

    $resolvedRoot = [IO.Path]::GetFullPath($Root).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $resolvedCandidate = [IO.Path]::GetFullPath($Candidate)
    $prefix = $resolvedRoot + [IO.Path]::DirectorySeparatorChar

    if (-not $resolvedCandidate.StartsWith(
            $prefix,
            [StringComparison]::OrdinalIgnoreCase
        )) {
        throw "Run directory must be a child of the configured artifact root."
    }

    return $resolvedCandidate
}

function Read-Configuration {
    param([string]$Path)

    $settings = [ordered]@{
        defaultWorkers           = 8
        workerModel              = "claude-haiku-4.5"
        workerContext            = "default"
        workerTimeoutSeconds     = 900
        workerMaxAiCredits       = $null
        hardWorkerLimit          = $null
        artifactRoot             = $null
        retainArtifactsOnSuccess = $false
        allowAllUrls             = $true
        readOnlyMcpServers       = @()
        readOnlyMcpTools         = @()
        disabledMcpServers       = @()
        excludedTools            = @("task", "ask_user")
    }

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        foreach ($key in @($settings.Keys)) {
            if (Test-Property -InputObject $config -Name $key) {
                $settings[$key] = Get-PropertyValue -InputObject $config -Name $key
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($env:WORKFLOW_GOAL_WORKERS)) {
        $settings.defaultWorkers = ConvertTo-PositiveInt `
            -Value $env:WORKFLOW_GOAL_WORKERS `
            -Name "WORKFLOW_GOAL_WORKERS"
    }
    if (-not [string]::IsNullOrWhiteSpace($env:WORKFLOW_GOAL_MODEL)) {
        $settings.workerModel = $env:WORKFLOW_GOAL_MODEL
    }
    if (-not [string]::IsNullOrWhiteSpace($env:WORKFLOW_GOAL_CONTEXT)) {
        $settings.workerContext = $env:WORKFLOW_GOAL_CONTEXT
    }
    if (-not [string]::IsNullOrWhiteSpace($env:WORKFLOW_GOAL_TIMEOUT_SECONDS)) {
        $settings.workerTimeoutSeconds = ConvertTo-PositiveInt `
            -Value $env:WORKFLOW_GOAL_TIMEOUT_SECONDS `
            -Name "WORKFLOW_GOAL_TIMEOUT_SECONDS"
    }
    if (-not [string]::IsNullOrWhiteSpace($env:WORKFLOW_GOAL_MAX_AI_CREDITS)) {
        $settings.workerMaxAiCredits = ConvertTo-OptionalPositiveDouble `
            -Value $env:WORKFLOW_GOAL_MAX_AI_CREDITS `
            -Name "WORKFLOW_GOAL_MAX_AI_CREDITS"
    }
    if (-not [string]::IsNullOrWhiteSpace($env:WORKFLOW_GOAL_HARD_WORKER_LIMIT)) {
        $settings.hardWorkerLimit = ConvertTo-PositiveInt `
            -Value $env:WORKFLOW_GOAL_HARD_WORKER_LIMIT `
            -Name "WORKFLOW_GOAL_HARD_WORKER_LIMIT"
    }
    if (-not [string]::IsNullOrWhiteSpace($env:WORKFLOW_GOAL_ARTIFACT_ROOT)) {
        $settings.artifactRoot = $env:WORKFLOW_GOAL_ARTIFACT_ROOT
    }
    if (-not [string]::IsNullOrWhiteSpace($env:WORKFLOW_GOAL_RETAIN_ARTIFACTS)) {
        $settings.retainArtifactsOnSuccess = ConvertTo-Boolean `
            -Value $env:WORKFLOW_GOAL_RETAIN_ARTIFACTS `
            -Name "WORKFLOW_GOAL_RETAIN_ARTIFACTS"
    }

    return [PSCustomObject]$settings
}

function Add-Argument {
    param(
        [Diagnostics.ProcessStartInfo]$StartInfo,
        [string]$Value
    )

    [void]$StartInfo.ArgumentList.Add($Value)
}

function New-WorkerPrompt {
    param(
        [string]$Goal,
        [object]$Task
    )

    $title = [string](Get-PropertyValue -InputObject $Task -Name "title")
    $prompt = [string](Get-PropertyValue -InputObject $Task -Name "prompt")

    return @"
You are one read-only worker in a parent-controlled workflow goal.

Goal context:
$Goal

Assigned topic:
$title

Task:
$prompt

Hard rules:
- Perform only read-only research and analysis.
- You may read/search local files, search/fetch the web, and use available read-only MCP tools.
- Do not modify files, run shell commands, store memories, invoke /workflow-goal, /goal, or /fleet, launch subagents, or ask the user questions.
- Do not claim that the parent goal is complete.
- Cite exact files and line ranges, URLs, or MCP sources for important claims.
- If evidence is missing or conflicting, say so explicitly.

Return exactly these Markdown sections:

## Findings
- Concrete findings with citations.

## Evidence
- Exact paths, line ranges, URLs, or MCP sources.

## Risks and unknowns
- Missing context, uncertainty, or conflicting evidence.

## Recommended parent action
- One concise next step for the parent session.
"@
}

function New-CopilotArguments {
    param(
        [object]$Settings,
        [string]$Repository,
        [string]$Prompt
    )

    $arguments = [Collections.Generic.List[string]]::new()
    foreach ($prefixArgument in $CopilotPrefixArguments) {
        $arguments.Add($prefixArgument)
    }

    $arguments.Add("-C")
    $arguments.Add($Repository)
    $arguments.Add("-p")
    $arguments.Add($Prompt)
    $arguments.Add("-s")
    $arguments.Add("--no-ask-user")
    $arguments.Add("--no-remote")
    $arguments.Add("--no-auto-update")
    $arguments.Add("--stream")
    $arguments.Add("off")
    $arguments.Add("--output-format")
    $arguments.Add("text")
    $arguments.Add("--model")
    $arguments.Add([string]$Settings.workerModel)
    $arguments.Add("--context")
    $arguments.Add([string]$Settings.workerContext)
    $arguments.Add("--deny-tool=shell,write,memory")

    if (@($Settings.excludedTools).Count -gt 0) {
        $arguments.Add("--excluded-tools=$(@($Settings.excludedTools) -join ',')")
    }

    $allowedTools = [Collections.Generic.List[string]]::new()
    $allowedTools.Add("read")

    foreach ($server in @($Settings.readOnlyMcpServers)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$server)) {
            $allowedTools.Add([string]$server)
        }
    }

    foreach ($entry in @($Settings.readOnlyMcpTools)) {
        $server = [string](Get-PropertyValue -InputObject $entry -Name "server")
        foreach ($tool in @(Get-PropertyValue -InputObject $entry -Name "tools" -DefaultValue @())) {
            if (-not [string]::IsNullOrWhiteSpace($server) -and
                -not [string]::IsNullOrWhiteSpace([string]$tool)) {
                $allowedTools.Add("$server($tool)")
            }
        }
    }

    if ($allowedTools.Count -gt 0) {
        $arguments.Add("--allow-tool=$($allowedTools -join ',')")
    }

    if ([bool]$Settings.allowAllUrls) {
        $arguments.Add("--allow-all-urls")
    }

    foreach ($server in @($Settings.disabledMcpServers)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$server)) {
            $arguments.Add("--disable-mcp-server")
            $arguments.Add([string]$server)
        }
    }

    if ($null -ne $Settings.workerMaxAiCredits) {
        $arguments.Add("--max-ai-credits")
        $arguments.Add(
            ([double]$Settings.workerMaxAiCredits).ToString(
                [Globalization.CultureInfo]::InvariantCulture
            )
        )
    }

    return $arguments
}

function Get-TaskKey {
    param(
        [object]$Task,
        [object]$Settings,
        [string]$Repository
    )

    $mcpTools = foreach ($entry in @($Settings.readOnlyMcpTools)) {
        $server = [string](Get-PropertyValue -InputObject $entry -Name "server")
        foreach ($tool in @(Get-PropertyValue -InputObject $entry -Name "tools" -DefaultValue @())) {
            "$server($tool)"
        }
    }

    $canonical = [ordered]@{
        repository         = $Repository.ToLowerInvariant()
        id                 = [string](Get-PropertyValue -InputObject $Task -Name "id")
        prompt             = ([string](Get-PropertyValue -InputObject $Task -Name "prompt")).Trim()
        model              = [string]$Settings.workerModel
        context            = [string]$Settings.workerContext
        allowAllUrls       = [bool]$Settings.allowAllUrls
        readOnlyMcpServers = @($Settings.readOnlyMcpServers | Sort-Object)
        readOnlyMcpTools   = @($mcpTools | Sort-Object)
    } | ConvertTo-Json -Depth 10 -Compress

    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical))
        return ([BitConverter]::ToString($hash) -replace "-", "").ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
}

$configuration = Read-Configuration -Path $ConfigPath
$artifactRoot = Resolve-ArtifactRoot -Settings $configuration

if ($Mode -eq "Cleanup") {
    if ([string]::IsNullOrWhiteSpace($RunDirectory)) {
        throw "RunDirectory is required in Cleanup mode."
    }

    $resolvedRunDirectory = Assert-ChildPath `
        -Root $artifactRoot `
        -Candidate $RunDirectory

    $existingManifestPath = Join-Path $resolvedRunDirectory "run-manifest.json"
    if (Test-Path -LiteralPath $existingManifestPath -PathType Leaf) {
        $existingManifest = Get-Content -LiteralPath $existingManifestPath -Raw |
            ConvertFrom-Json
        $existingStatus = [string](
            Get-PropertyValue -InputObject $existingManifest -Name "status"
        )
        $helperProcessId = Get-PropertyValue `
            -InputObject $existingManifest `
            -Name "helperProcessId"
        if ($existingStatus -in @("starting", "running") -and
            $null -ne $helperProcessId -and
            $null -ne (Get-Process -Id ([int]$helperProcessId) -ErrorAction SilentlyContinue)) {
            throw "Run is still active. Cancel it before cleanup."
        }
    }

    if (Test-Path -LiteralPath $resolvedRunDirectory) {
        Remove-Item -LiteralPath $resolvedRunDirectory -Recurse -Force
    }

    [PSCustomObject]@{
        mode         = "cleanup"
        runDirectory = $resolvedRunDirectory
        removed      = -not (Test-Path -LiteralPath $resolvedRunDirectory)
    } | ConvertTo-Json -Compress
    exit 0
}

if ($Mode -eq "Cancel") {
    if ([string]::IsNullOrWhiteSpace($RunDirectory)) {
        throw "RunDirectory is required in Cancel mode."
    }

    $resolvedRunDirectory = Assert-ChildPath `
        -Root $artifactRoot `
        -Candidate $RunDirectory

    for ($attempt = 0; $attempt -lt 50 -and
        -not (Test-Path -LiteralPath $resolvedRunDirectory -PathType Container);
        $attempt++) {
        Start-Sleep -Milliseconds 100
    }
    if (-not (Test-Path -LiteralPath $resolvedRunDirectory -PathType Container)) {
        throw "Run directory did not appear before the cancellation timeout."
    }

    $cancelPath = Join-Path $resolvedRunDirectory "cancel.requested"
    [IO.File]::WriteAllText(
        $cancelPath,
        [DateTimeOffset]::UtcNow.ToString("o"),
        [Text.UTF8Encoding]::new($false)
    )

    $manifestPath = Join-Path $resolvedRunDirectory "run-manifest.json"
    $stoppedProcessIds = [Collections.Generic.List[int]]::new()
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        foreach ($task in @(Get-PropertyValue -InputObject $manifest -Name "tasks" -DefaultValue @())) {
            $processId = Get-PropertyValue -InputObject $task -Name "processId"
            $taskStatus = [string](Get-PropertyValue -InputObject $task -Name "status")
            if ($taskStatus -eq "running" -and $null -ne $processId) {
                $process = Get-Process -Id ([int]$processId) -ErrorAction SilentlyContinue
                if ($null -ne $process) {
                    Stop-Process -Id ([int]$processId) -Force
                    $stoppedProcessIds.Add([int]$processId)
                }
            }
        }
    }

    $finalStatus = "cancellation_requested"
    for ($attempt = 0; $attempt -lt 300; $attempt++) {
        if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw |
                ConvertFrom-Json
            $finalStatus = [string](
                Get-PropertyValue -InputObject $manifest -Name "status"
            )
            if ($finalStatus -notin @("starting", "running")) {
                break
            }
        }
        Start-Sleep -Milliseconds 100
    }

    [PSCustomObject]@{
        mode              = "cancel"
        runDirectory      = $resolvedRunDirectory
        status            = $finalStatus
        stoppedProcessIds = @($stoppedProcessIds)
    } | ConvertTo-Json -Depth 5 -Compress
    exit 0
}

if ([string]::IsNullOrWhiteSpace($TasksFile) -or
    -not (Test-Path -LiteralPath $TasksFile -PathType Leaf)) {
    throw "TasksFile must reference an existing JSON file in Run mode."
}

$tasksManifest = Get-Content -LiteralPath $TasksFile -Raw | ConvertFrom-Json
$tasks = @(Get-PropertyValue -InputObject $tasksManifest -Name "tasks" -DefaultValue @())
if ($tasks.Count -lt 1) {
    throw "The task manifest must contain at least one task."
}

$repository = [string](Get-PropertyValue -InputObject $tasksManifest -Name "repository")
if ([string]::IsNullOrWhiteSpace($repository) -or
    -not (Test-Path -LiteralPath $repository -PathType Container)) {
    throw "The task manifest repository must reference an existing directory."
}
$repository = [IO.Path]::GetFullPath($repository)

$runId = [string](Get-PropertyValue -InputObject $tasksManifest -Name "runId")
if ([string]::IsNullOrWhiteSpace($runId)) {
    $runId = "workflow-goal-$([Guid]::NewGuid().ToString('N'))"
}
if ($runId -notmatch "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$") {
    throw "runId contains unsupported characters or exceeds 128 characters."
}

$effective = [ordered]@{
    defaultWorkers           = ConvertTo-PositiveInt `
        -Value $configuration.defaultWorkers `
        -Name "defaultWorkers"
    workerModel              = [string]$configuration.workerModel
    workerContext            = [string]$configuration.workerContext
    workerTimeoutSeconds     = ConvertTo-PositiveInt `
        -Value $configuration.workerTimeoutSeconds `
        -Name "workerTimeoutSeconds"
    workerMaxAiCredits       = ConvertTo-OptionalPositiveDouble `
        -Value $configuration.workerMaxAiCredits `
        -Name "workerMaxAiCredits"
    hardWorkerLimit          = if ($null -eq $configuration.hardWorkerLimit) {
        $null
    } else {
        ConvertTo-PositiveInt `
            -Value $configuration.hardWorkerLimit `
            -Name "hardWorkerLimit"
    }
    artifactRoot             = $artifactRoot
    retainArtifactsOnSuccess = [bool]$configuration.retainArtifactsOnSuccess
    allowAllUrls             = [bool]$configuration.allowAllUrls
    readOnlyMcpServers       = @($configuration.readOnlyMcpServers)
    readOnlyMcpTools         = @($configuration.readOnlyMcpTools)
    disabledMcpServers       = @($configuration.disabledMcpServers)
    excludedTools            = @($configuration.excludedTools)
}

if ($PSBoundParameters.ContainsKey("Workers")) {
    $effective.defaultWorkers = ConvertTo-PositiveInt -Value $Workers -Name "Workers"
}
if ($PSBoundParameters.ContainsKey("WorkerModel")) {
    $effective.workerModel = $WorkerModel
}
if ($PSBoundParameters.ContainsKey("WorkerContext")) {
    $effective.workerContext = $WorkerContext
}
if ($PSBoundParameters.ContainsKey("WorkerTimeoutSeconds")) {
    $effective.workerTimeoutSeconds = ConvertTo-PositiveInt `
        -Value $WorkerTimeoutSeconds `
        -Name "WorkerTimeoutSeconds"
}
if ($PSBoundParameters.ContainsKey("WorkerMaxAiCredits")) {
    $effective.workerMaxAiCredits = ConvertTo-OptionalPositiveDouble `
        -Value $WorkerMaxAiCredits `
        -Name "WorkerMaxAiCredits"
}
if ($PSBoundParameters.ContainsKey("HardWorkerLimit")) {
    $effective.hardWorkerLimit = if ($null -eq $HardWorkerLimit) {
        $null
    } else {
        ConvertTo-PositiveInt -Value $HardWorkerLimit -Name "HardWorkerLimit"
    }
}

$manifestSettings = Get-PropertyValue -InputObject $tasksManifest -Name "settings"
if (Test-Property -InputObject $manifestSettings -Name "workers") {
    $effective.defaultWorkers = ConvertTo-PositiveInt `
        -Value (Get-PropertyValue -InputObject $manifestSettings -Name "workers") `
        -Name "manifest settings.workers"
}
if (Test-Property -InputObject $manifestSettings -Name "model") {
    $effective.workerModel = [string](
        Get-PropertyValue -InputObject $manifestSettings -Name "model"
    )
}
if (Test-Property -InputObject $manifestSettings -Name "context") {
    $effective.workerContext = [string](
        Get-PropertyValue -InputObject $manifestSettings -Name "context"
    )
}
if (Test-Property -InputObject $manifestSettings -Name "timeoutSeconds") {
    $effective.workerTimeoutSeconds = ConvertTo-PositiveInt `
        -Value (Get-PropertyValue -InputObject $manifestSettings -Name "timeoutSeconds") `
        -Name "manifest settings.timeoutSeconds"
}
if (Test-Property -InputObject $manifestSettings -Name "maxAiCredits") {
    $effective.workerMaxAiCredits = ConvertTo-OptionalPositiveDouble `
        -Value (Get-PropertyValue -InputObject $manifestSettings -Name "maxAiCredits") `
        -Name "manifest settings.maxAiCredits"
}
if (Test-Property -InputObject $manifestSettings -Name "hardWorkerLimit") {
    $manifestHardLimit = Get-PropertyValue `
        -InputObject $manifestSettings `
        -Name "hardWorkerLimit"
    $effective.hardWorkerLimit = if ($null -eq $manifestHardLimit) {
        $null
    } else {
        ConvertTo-PositiveInt `
            -Value $manifestHardLimit `
            -Name "manifest settings.hardWorkerLimit"
    }
}

if ([string]::IsNullOrWhiteSpace($effective.workerModel)) {
    throw "The effective worker model cannot be empty."
}
if ($effective.workerContext -notin @("default", "long_context")) {
    throw "The effective worker context must be default or long_context."
}

$maxConcurrency = [Math]::Min([int]$effective.defaultWorkers, $tasks.Count)
if ($null -ne $effective.hardWorkerLimit -and
    $maxConcurrency -gt [int]$effective.hardWorkerLimit) {
    throw "Requested worker count $maxConcurrency exceeds hardWorkerLimit $($effective.hardWorkerLimit)."
}

$seenIds = @{}
foreach ($task in $tasks) {
    $taskId = [string](Get-PropertyValue -InputObject $task -Name "id")
    $taskPrompt = [string](Get-PropertyValue -InputObject $task -Name "prompt")

    if ($taskId -notmatch "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$") {
        throw "Task id '$taskId' is invalid."
    }
    if ($seenIds.ContainsKey($taskId)) {
        throw "Task id '$taskId' is duplicated."
    }
    if ([string]::IsNullOrWhiteSpace($taskPrompt)) {
        throw "Task '$taskId' has an empty prompt."
    }
    if ($taskPrompt.Length -gt 20000) {
        throw "Task '$taskId' exceeds the 20000-character prompt limit."
    }

    $seenIds[$taskId] = $true
}

$runDirectoryPath = Join-Path $artifactRoot $runId
if (Test-Path -LiteralPath $runDirectoryPath) {
    throw "Run directory already exists: $runDirectoryPath"
}

New-Item -ItemType Directory -Path $runDirectoryPath -Force | Out-Null
$cancelPath = Join-Path $runDirectoryPath "cancel.requested"
Copy-Item -LiteralPath $TasksFile -Destination (
    Join-Path $runDirectoryPath "input-manifest.json"
)

$goal = [string](Get-PropertyValue -InputObject $tasksManifest -Name "goal")
$taskRecords = [Collections.Generic.List[object]]::new()
foreach ($task in $tasks) {
    $taskId = [string](Get-PropertyValue -InputObject $task -Name "id")
    $taskDirectory = Join-Path $runDirectoryPath $taskId
    New-Item -ItemType Directory -Path $taskDirectory -Force | Out-Null

    $taskRecords.Add([PSCustomObject]@{
        id         = $taskId
        taskKey    = Get-TaskKey `
            -Task $task `
            -Settings ([PSCustomObject]$effective) `
            -Repository $repository
        title      = [string](Get-PropertyValue -InputObject $task -Name "title")
        status     = "queued"
        processId  = $null
        startedAt  = $null
        completedAt = $null
        durationMs = $null
        exitCode   = $null
        resultPath = Join-Path $taskDirectory "result.md"
        stderrPath = Join-Path $taskDirectory "stderr.log"
        error      = $null
    })
}

$runManifestPath = Join-Path $runDirectoryPath "run-manifest.json"
$runState = [PSCustomObject]@{
    runId             = $runId
    status            = "starting"
    helperProcessId   = $PID
    repository        = $repository
    startedAt         = [DateTimeOffset]::UtcNow.ToString("o")
    completedAt       = $null
    cancellationRequestedAt = $null
    requestedTasks    = $tasks.Count
    maxConcurrency    = $maxConcurrency
    workerModel       = $effective.workerModel
    workerContext     = $effective.workerContext
    timeoutSeconds    = $effective.workerTimeoutSeconds
    artifactRetention = [bool]$effective.retainArtifactsOnSuccess
    tasks             = $taskRecords
}
Write-JsonAtomic -Path $runManifestPath -Value $runState
$runState.status = "running"
Write-JsonAtomic -Path $runManifestPath -Value $runState

$pending = [Collections.Queue]::new()
for ($index = 0; $index -lt $tasks.Count; $index++) {
    $pending.Enqueue([PSCustomObject]@{
        task   = $tasks[$index]
        record = $taskRecords[$index]
    })
}

$active = [Collections.Generic.List[object]]::new()
$utf8NoBom = [Text.UTF8Encoding]::new($false)

while ($pending.Count -gt 0 -or $active.Count -gt 0) {
    $cancelRequested = Test-Path -LiteralPath $cancelPath -PathType Leaf
    if ($cancelRequested) {
        if ($null -eq $runState.cancellationRequestedAt) {
            $runState.cancellationRequestedAt = [DateTimeOffset]::UtcNow.ToString("o")
        }
        while ($pending.Count -gt 0) {
            $cancelledItem = $pending.Dequeue()
            $cancelledItem.record.status = "cancelled"
            $cancelledItem.record.completedAt = [DateTimeOffset]::UtcNow.ToString("o")
            $cancelledItem.record.error = "Cancelled before launch."
        }
        foreach ($entry in @($active)) {
            if (-not $entry.process.HasExited) {
                Stop-Process -Id $entry.process.Id -Force -ErrorAction SilentlyContinue
            }
        }
        Write-JsonAtomic -Path $runManifestPath -Value $runState
    }

    while ($pending.Count -gt 0 -and
        $active.Count -lt $maxConcurrency -and
        -not (Test-Path -LiteralPath $cancelPath -PathType Leaf)) {
        $workItem = $pending.Dequeue()
        $workerPrompt = New-WorkerPrompt -Goal $goal -Task $workItem.task
        $arguments = New-CopilotArguments `
            -Settings ([PSCustomObject]$effective) `
            -Repository $repository `
            -Prompt $workerPrompt

        try {
            $startInfo = [Diagnostics.ProcessStartInfo]::new()
            $startInfo.FileName = $CopilotExecutable
            $startInfo.UseShellExecute = $false
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            $startInfo.CreateNoWindow = $true

            foreach ($argument in $arguments) {
                Add-Argument -StartInfo $startInfo -Value $argument
            }

            $process = [Diagnostics.Process]::new()
            $process.StartInfo = $startInfo
            if (-not $process.Start()) {
                throw "Process start returned false."
            }

            $workItem.record.status = "running"
            $workItem.record.processId = $process.Id
            $workItem.record.startedAt = [DateTimeOffset]::UtcNow.ToString("o")
            $active.Add([PSCustomObject]@{
                process    = $process
                record     = $workItem.record
                started    = [DateTimeOffset]::UtcNow
                stdoutTask = $process.StandardOutput.ReadToEndAsync()
                stderrTask = $process.StandardError.ReadToEndAsync()
            })
        } catch {
            $workItem.record.status = "failed"
            $workItem.record.completedAt = [DateTimeOffset]::UtcNow.ToString("o")
            $workItem.record.error = "Failed to launch worker: $($_.Exception.Message)"
        }

        Write-JsonAtomic -Path $runManifestPath -Value $runState
    }

    for ($index = $active.Count - 1; $index -ge 0; $index--) {
        $entry = $active[$index]
        $elapsed = [DateTimeOffset]::UtcNow - $entry.started
        $cancelRequested = Test-Path -LiteralPath $cancelPath -PathType Leaf
        $timedOut = -not $cancelRequested -and
            $elapsed.TotalSeconds -ge [int]$effective.workerTimeoutSeconds

        if (-not $entry.process.HasExited -and
            -not $timedOut -and
            -not $cancelRequested) {
            continue
        }

        if (($timedOut -or $cancelRequested) -and -not $entry.process.HasExited) {
            try {
                $entry.process.Kill($true)
            } catch {
                $entry.process.Kill()
            }
            $entry.process.WaitForExit()
        }

        $stdout = $entry.stdoutTask.GetAwaiter().GetResult()
        $stderr = $entry.stderrTask.GetAwaiter().GetResult()
        [IO.File]::WriteAllText($entry.record.resultPath, $stdout, $utf8NoBom)
        [IO.File]::WriteAllText($entry.record.stderrPath, $stderr, $utf8NoBom)

        $entry.record.completedAt = [DateTimeOffset]::UtcNow.ToString("o")
        $entry.record.durationMs = [Math]::Round($elapsed.TotalMilliseconds)

        if ($cancelRequested) {
            $entry.record.status = "cancelled"
            $entry.record.error = "Cancelled by parent request."
        } elseif ($timedOut) {
            $entry.record.status = "timed_out"
            $entry.record.error = "Worker exceeded $($effective.workerTimeoutSeconds) seconds."
        } else {
            $entry.record.exitCode = $entry.process.ExitCode
            if ($entry.process.ExitCode -ne 0) {
                $entry.record.status = "failed"
                $entry.record.error = "Copilot exited with code $($entry.process.ExitCode)."
            } elseif ([string]::IsNullOrWhiteSpace($stdout)) {
                $entry.record.status = "failed"
                $entry.record.error = "Copilot returned empty output."
            } else {
                $entry.record.status = "succeeded"
            }
        }

        $entry.process.Dispose()
        $active.RemoveAt($index)
        Write-JsonAtomic -Path $runManifestPath -Value $runState
    }

    if ($active.Count -gt 0) {
        Start-Sleep -Milliseconds 100
    }
}

$succeeded = @($taskRecords | Where-Object status -eq "succeeded")
$failed = @($taskRecords | Where-Object status -eq "failed")
$timedOut = @($taskRecords | Where-Object status -eq "timed_out")
$cancelled = @($taskRecords | Where-Object status -eq "cancelled")

$runState.completedAt = [DateTimeOffset]::UtcNow.ToString("o")
$runState.status = if ($cancelled.Count -gt 0) {
    "cancelled"
} elseif ($succeeded.Count -eq $tasks.Count) {
    "succeeded"
} elseif ($succeeded.Count -gt 0) {
    "partial"
} else {
    "failed"
}
Write-JsonAtomic -Path $runManifestPath -Value $runState

[PSCustomObject]@{
    mode                     = "run"
    runId                    = $runId
    status                   = $runState.status
    runDirectory             = $runDirectoryPath
    manifestPath             = $runManifestPath
    requestedTasks           = $tasks.Count
    succeeded                = $succeeded.Count
    failed                   = $failed.Count
    timedOut                 = $timedOut.Count
    cancelled                = $cancelled.Count
    workers                  = $maxConcurrency
    model                    = $effective.workerModel
    context                  = $effective.workerContext
    retainArtifactsOnSuccess = [bool]$effective.retainArtifactsOnSuccess
    succeededTaskKeys        = @($succeeded | ForEach-Object taskKey)
    results                  = @(
        $taskRecords |
            Select-Object id, taskKey, status, resultPath, stderrPath, error
    )
} | ConvertTo-Json -Depth 10 -Compress
