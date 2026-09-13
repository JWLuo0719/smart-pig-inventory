[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaselineManifest,
    [Parameter(Mandatory = $true)][string]$CandidateManifest,
    [string]$ComposeProjectName = 'pig-inventory-p1-rollback',
    [int]$InferencePort = 18100,
    [int]$FaultRunnerPort = 19100,
    [int]$ReadinessTimeoutSeconds = 60,
    [switch]$KeepStack
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$baseCompose = Join-Path $repositoryRoot 'docker-compose.yml'
$faultCompose = Join-Path $repositoryRoot 'docker-compose.fault-e2e.yml'
$releaseTool = Join-Path $PSScriptRoot 'model_release_gate.py'
$generatedDirectory = Join-Path $repositoryRoot 'test-assets\generated'
$controlHeaders = @{ 'X-Fault-Control-Key' = 'local-e2e-only' }
$completed = $false

function Invoke-RollbackCompose {
    param([string[]]$ComposeArguments)

    & docker compose -p $ComposeProjectName -f $baseCompose -f $faultCompose @ComposeArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose failed with exit code $LASTEXITCODE."
    }
}

function Get-HttpResult {
    param([string]$Uri)

    try {
        $response = Invoke-WebRequest -Uri $Uri -TimeoutSec 3 -SkipHttpErrorCheck
        return [pscustomobject]@{ Status = [int]$response.StatusCode; Body = [string]$response.Content }
    }
    catch {
        return [pscustomobject]@{ Status = 0; Body = '' }
    }
}

function Wait-HttpStatus {
    param(
        [string]$Uri,
        [int]$ExpectedStatus,
        [int]$TimeoutSeconds
    )

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    $lastResult = $null
    do {
        $lastResult = Get-HttpResult -Uri $Uri
        if ($lastResult.Status -eq $ExpectedStatus) {
            return $lastResult
        }
        Start-Sleep -Milliseconds 250
    } while ([DateTimeOffset]::UtcNow -lt $deadline)
    $lastStatus = $lastResult.Status
    throw "Timed out waiting for HTTP $ExpectedStatus from $Uri. Last status: $lastStatus"
}

function Get-Identity {
    param([object]$Manifest)

    return [ordered]@{
        model_key = [string]$Manifest.model.model_key
        model_version = [string]$Manifest.model.model_version
        model_checksum = [string]$Manifest.model.model_checksum
        adapter_version = [string]$Manifest.model.adapter_version
    }
}

function Set-ExpectedIdentity {
    param([Collections.IDictionary]$Identity)

    $env:MODEL_KEY = $Identity.model_key
    $env:MODEL_VERSION = $Identity.model_version
    $env:MODEL_CHECKSUM = $Identity.model_checksum
    $env:MODEL_ADAPTER_VERSION = $Identity.adapter_version
}

function Set-RunnerState {
    param(
        [ValidateSet('ready', 'not_ready', 'timeout')][string]$Mode,
        [Collections.IDictionary]$Identity
    )

    $payload = [ordered]@{
        mode = $Mode
        delay_seconds = 1
        model_identity = $Identity
    }
    $body = $payload | ConvertTo-Json -Depth 6
    Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:$FaultRunnerPort/control" `
        -Headers $controlHeaders -ContentType 'application/json' -Body $body | Out-Null
}

function Start-IdentityStack {
    param([Collections.IDictionary]$Identity)

    Set-ExpectedIdentity -Identity $Identity
    Invoke-RollbackCompose -ComposeArguments @(
        'up', '-d', '--build', '--force-recreate',
        'redis', 'inference-fault-runner', 'inference-api', 'inference-worker'
    )
    Wait-HttpStatus -Uri "http://127.0.0.1:$FaultRunnerPort/health/live" `
        -ExpectedStatus 200 -TimeoutSeconds $ReadinessTimeoutSeconds | Out-Null
    Set-RunnerState -Mode ready -Identity $Identity
    Wait-HttpStatus -Uri "http://127.0.0.1:$InferencePort/health/ready" `
        -ExpectedStatus 200 -TimeoutSeconds $ReadinessTimeoutSeconds | Out-Null
}

try {
    if ($ComposeProjectName -ne 'pig-inventory-p1-rollback') {
        throw 'The rollback rehearsal may only use the isolated pig-inventory-p1-rollback Compose project.'
    }
    foreach ($manifestPath in @($BaselineManifest, $CandidateManifest)) {
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            throw "Release manifest does not exist: $manifestPath"
        }
        & python $releaseTool validate-manifest --manifest $manifestPath
        if ($LASTEXITCODE -ne 0) {
            throw "Release manifest validation failed: $manifestPath"
        }
    }
    $baseline = Get-Content -LiteralPath $BaselineManifest -Raw | ConvertFrom-Json
    $candidate = Get-Content -LiteralPath $CandidateManifest -Raw | ConvertFrom-Json
    $baselineIdentity = Get-Identity -Manifest $baseline
    $candidateIdentity = Get-Identity -Manifest $candidate
    if ($baseline.release_id -eq $candidate.release_id) {
        throw 'Baseline and candidate release IDs must differ.'
    }

    New-Item -ItemType Directory -Force -Path $generatedDirectory | Out-Null
    $env:FAULT_INFERENCE_PORT = $InferencePort.ToString()
    $env:FAULT_RUNNER_CONTROL_PORT = $FaultRunnerPort.ToString()
    $env:FAULT_PROVIDER_TIMEOUT_SECONDS = '2'
    $env:FAULT_DELAY_SECONDS = '5'

    Write-Output '[INFO] Starting the isolated rollback anchor release.'
    Start-IdentityStack -Identity $baselineIdentity

    Write-Output '[INFO] Deploying the candidate identity to the runner and inference boundary.'
    Start-IdentityStack -Identity $candidateIdentity

    Write-Output '[INFO] Injecting a corrupt candidate identity and checking fail-closed readiness.'
    $corruptIdentity = [ordered]@{
        model_key = $candidateIdentity.model_key
        model_version = $candidateIdentity.model_version
        model_checksum = 'f' * 64
        adapter_version = $candidateIdentity.adapter_version
    }
    Set-RunnerState -Mode ready -Identity $corruptIdentity
    $mismatchResult = Wait-HttpStatus -Uri "http://127.0.0.1:$InferencePort/health/ready" `
        -ExpectedStatus 503 -TimeoutSeconds $ReadinessTimeoutSeconds
    $mismatchPayload = $mismatchResult.Body | ConvertFrom-Json
    if ($mismatchPayload.reason_code -ne 'RUNNER_IDENTITY_MISMATCH') {
        $actualReason = $mismatchPayload.reason_code
        throw "Expected RUNNER_IDENTITY_MISMATCH, received: $actualReason"
    }

    Write-Output '[INFO] Rolling back both configured and reported identity to the anchor release.'
    $rollbackTimer = [Diagnostics.Stopwatch]::StartNew()
    Start-IdentityStack -Identity $baselineIdentity
    $rollbackTimer.Stop()

    $summary = [ordered]@{
        completed_at = [DateTimeOffset]::UtcNow.ToString('o')
        compose_project = $ComposeProjectName
        baseline_release_id = [string]$baseline.release_id
        candidate_release_id = [string]$candidate.release_id
        candidate_deployment = 'passed'
        corrupt_identity_gate = 'RUNNER_IDENTITY_MISMATCH'
        rollback_readiness = 'passed'
        rollback_elapsed_ms = $rollbackTimer.ElapsedMilliseconds
        business_data_touched = $false
        automatic_counting_enabled = $false
        data_classification = 'local ignored synthetic rollback evidence'
    }
    $summaryPath = Join-Path $generatedDirectory 'model-rollback-rehearsal-summary.json'
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8
    Write-Output "[OK] Model rollback rehearsal passed. Summary: $summaryPath"
    $completed = $true
}
catch {
    Write-Error $_
    exit 1
}
finally {
    if ((-not $KeepStack) -and $completed) {
        Invoke-RollbackCompose -ComposeArguments @('down')
    }
    elseif (-not $completed) {
        Write-Warning "Rollback rehearsal stack retained for diagnostics: $ComposeProjectName"
    }
}
