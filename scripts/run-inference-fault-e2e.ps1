[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ImagePath,
    [string]$ComposeProjectName = 'pig-inventory-p1-fault',
    [int]$GatewayPort = 8090,
    [int]$InferencePort = 18000,
    [int]$FaultRunnerPort = 19090,
    [int]$ReadinessTimeoutSeconds = 45,
    [switch]$KeepStack
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$baseCompose = Join-Path $repositoryRoot 'docker-compose.yml'
$faultCompose = Join-Path $repositoryRoot 'docker-compose.fault-e2e.yml'
$generatedDirectory = Join-Path $repositoryRoot 'test-assets\generated'
$controlHeaders = @{ 'X-Fault-Control-Key' = 'local-e2e-only' }
$completed = $false

function Invoke-FaultCompose {
    param([string[]]$ComposeArguments)

    & docker compose -p $ComposeProjectName -f $baseCompose -f $faultCompose @ComposeArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose failed with exit code $LASTEXITCODE."
    }
}

function Get-HttpStatus {
    param([string]$Uri)

    try {
        $response = Invoke-WebRequest -Uri $Uri -TimeoutSec 3 -SkipHttpErrorCheck
        return [int]$response.StatusCode
    }
    catch {
        return 0
    }
}

function Wait-HttpStatus {
    param(
        [string]$Uri,
        [int]$ExpectedStatus,
        [int]$TimeoutSeconds
    )

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $actualStatus = Get-HttpStatus -Uri $Uri
        if ($actualStatus -eq $ExpectedStatus) {
            return
        }
        Start-Sleep -Milliseconds 250
    } while ([DateTimeOffset]::UtcNow -lt $deadline)
    throw "Timed out waiting for HTTP $ExpectedStatus from $Uri. Last status: $actualStatus"
}

function Wait-HttpFailClosed {
    param(
        [string]$Uri,
        [int]$TimeoutSeconds
    )

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $actualStatus = Get-HttpStatus -Uri $Uri
        if ($actualStatus -in @(0, 503)) {
            return
        }
        Start-Sleep -Milliseconds 250
    } while ([DateTimeOffset]::UtcNow -lt $deadline)
    throw "Readiness did not fail closed after the runner stopped. Last status: $actualStatus"
}

function Set-FaultMode {
    param(
        [ValidateSet('ready', 'not_ready', 'timeout')][string]$Mode,
        [double]$DelaySeconds = 5
    )

    $body = @{ mode = $Mode; delay_seconds = $DelaySeconds } | ConvertTo-Json -Depth 4
    Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:$FaultRunnerPort/control" `
        -Headers $controlHeaders -ContentType 'application/json' -Body $body | Out-Null
}

function New-UniqueTestImage {
    param(
        [string]$SourcePath,
        [string]$Scenario
    )

    $destination = Join-Path $generatedDirectory ("fault-$Scenario-$([guid]::NewGuid()).jpg")
    $sourceBytes = [IO.File]::ReadAllBytes($SourcePath)
    $nonceBytes = [Text.Encoding]::ASCII.GetBytes("`nFAULT-E2E-$([guid]::NewGuid())")
    $combined = [byte[]]::new($sourceBytes.Length + $nonceBytes.Length)
    [Array]::Copy($sourceBytes, 0, $combined, 0, $sourceBytes.Length)
    [Array]::Copy($nonceBytes, 0, $combined, $sourceBytes.Length, $nonceBytes.Length)
    [IO.File]::WriteAllBytes($destination, $combined)
    return $destination
}

try {
    if ($ComposeProjectName -ne 'pig-inventory-p1-fault') {
        throw 'The fault test may only use the isolated pig-inventory-p1-fault Compose project.'
    }
    $resolvedImagePath = [IO.Path]::GetFullPath($ImagePath)
    if (-not (Test-Path -LiteralPath $resolvedImagePath -PathType Leaf)) {
        throw 'The E2E image was not found.'
    }
    New-Item -ItemType Directory -Force -Path $generatedDirectory | Out-Null
    $env:GATEWAY_PORT = $GatewayPort.ToString()
    $env:FAULT_INFERENCE_PORT = $InferencePort.ToString()
    $env:FAULT_RUNNER_CONTROL_PORT = $FaultRunnerPort.ToString()
    $env:FAULT_PROVIDER_TIMEOUT_SECONDS = '2'
    $env:FAULT_DELAY_SECONDS = '5'

    Write-Output '[INFO] Starting the isolated inference boundary with the runner deliberately not ready.'
    Invoke-FaultCompose -ComposeArguments @('up', '-d', '--build', 'redis', 'inference-fault-runner', 'inference-api', 'inference-worker')
    Wait-HttpStatus -Uri "http://127.0.0.1:$FaultRunnerPort/health/live" -ExpectedStatus 200 -TimeoutSeconds $ReadinessTimeoutSeconds
    Set-FaultMode -Mode not_ready
    Wait-HttpStatus -Uri "http://127.0.0.1:$InferencePort/health/ready" -ExpectedStatus 503 -TimeoutSeconds $ReadinessTimeoutSeconds

    $coldStart = [Diagnostics.Stopwatch]::StartNew()
    Set-FaultMode -Mode ready
    Wait-HttpStatus -Uri "http://127.0.0.1:$InferencePort/health/ready" -ExpectedStatus 200 -TimeoutSeconds $ReadinessTimeoutSeconds
    $coldStart.Stop()

    Write-Output '[INFO] Starting the remaining isolated product services after readiness passes.'
    Invoke-FaultCompose -ComposeArguments @('up', '-d', '--build')
    Wait-HttpStatus -Uri "http://127.0.0.1:$GatewayPort/actuator/health" -ExpectedStatus 200 -TimeoutSeconds 180

    Write-Output '[INFO] Injecting a provider response timeout.'
    Set-FaultMode -Mode timeout -DelaySeconds 5
    $timeoutImage = New-UniqueTestImage -SourcePath $resolvedImagePath -Scenario 'timeout'
    & (Join-Path $PSScriptRoot 'run-local-research-count-e2e.ps1') `
        -ComposeProjectName $ComposeProjectName `
        -BaseUrl "http://127.0.0.1:$GatewayPort/api/v1" `
        -ImagePath $timeoutImage `
        -ExpectedFailureCode 'PROVIDER_TIMEOUT' `
        -TimeoutSeconds 120
    if (-not $?) {
        throw 'The timeout E2E scenario failed.'
    }

    Write-Output '[INFO] Stopping the runner container and verifying readiness fails closed.'
    Invoke-FaultCompose -ComposeArguments @('stop', 'inference-fault-runner')
    Wait-HttpFailClosed -Uri "http://127.0.0.1:$InferencePort/health/ready" -TimeoutSeconds $ReadinessTimeoutSeconds

    Write-Output '[INFO] Restarting the runner; it remains gated until its model readiness is explicit.'
    Invoke-FaultCompose -ComposeArguments @('start', 'inference-fault-runner')
    Wait-HttpStatus -Uri "http://127.0.0.1:$FaultRunnerPort/health/live" -ExpectedStatus 200 -TimeoutSeconds $ReadinessTimeoutSeconds
    Wait-HttpStatus -Uri "http://127.0.0.1:$InferencePort/health/ready" -ExpectedStatus 503 -TimeoutSeconds $ReadinessTimeoutSeconds
    $restartRecovery = [Diagnostics.Stopwatch]::StartNew()
    Set-FaultMode -Mode ready
    Wait-HttpStatus -Uri "http://127.0.0.1:$InferencePort/health/ready" -ExpectedStatus 200 -TimeoutSeconds $ReadinessTimeoutSeconds
    $restartRecovery.Stop()

    $recoveryImage = New-UniqueTestImage -SourcePath $resolvedImagePath -Scenario 'recovery'
    & (Join-Path $PSScriptRoot 'run-local-research-count-e2e.ps1') `
        -ComposeProjectName $ComposeProjectName `
        -BaseUrl "http://127.0.0.1:$GatewayPort/api/v1" `
        -ImagePath $recoveryImage `
        -ExpectedCandidateCount 1 `
        -TimeoutSeconds 120
    if (-not $?) {
        throw 'The post-restart recovery E2E scenario failed.'
    }

    $summary = [ordered]@{
        completed_at = [DateTimeOffset]::UtcNow.ToString('o')
        compose_project = $ComposeProjectName
        readiness_gate = 'passed'
        timeout_failure_code = 'PROVIDER_TIMEOUT'
        runner_stop_fail_closed = $true
        post_restart_recovery = 'passed'
        cold_gate_recovery_ms = $coldStart.ElapsedMilliseconds
        restart_gate_recovery_ms = $restartRecovery.ElapsedMilliseconds
        data_classification = 'local ignored synthetic fault evidence'
    }
    $summaryPath = Join-Path $generatedDirectory 'inference-fault-e2e-summary.json'
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8
    Write-Output "[OK] Fault injection E2E passed. Summary: $summaryPath"
    $completed = $true
}
catch {
    Write-Error $_
    exit 1
}
finally {
    if ((-not $KeepStack) -and $completed) {
        Invoke-FaultCompose -ComposeArguments @('down')
    }
    elseif (-not $completed) {
        Write-Warning "Fault stack retained for diagnostics: $ComposeProjectName"
    }
}
