[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ImagePath,
    [string]$ComposeProjectName = 'pig-inventory-p1-retry',
    [int]$GatewayPort = 8091,
    [int]$InferencePort = 18001,
    [int]$FaultRunnerPort = 19091,
    [int]$TimeoutSeconds = 180,
    [switch]$KeepStack
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$baseCompose = Join-Path $repositoryRoot 'docker-compose.yml'
$faultCompose = Join-Path $repositoryRoot 'docker-compose.fault-e2e.yml'
$envFile = Join-Path $repositoryRoot '.env'
$generatedDirectory = Join-Path $repositoryRoot 'test-assets\generated'
$controlHeaders = @{ 'X-Fault-Control-Key' = 'local-e2e-only' }
$completed = $false

function Invoke-RetryCompose {
    param([string[]]$ComposeArguments)

    & docker compose -p $ComposeProjectName -f $baseCompose -f $faultCompose @ComposeArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose failed with exit code $LASTEXITCODE."
    }
}

function Get-EnvValue {
    param([string]$Name)

    $pattern = '^' + [regex]::Escape($Name) + '=(.*)$'
    $line = Get-Content -LiteralPath $envFile | Where-Object { $_ -match $pattern } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($line)) {
        throw "Missing environment value: $Name"
    }
    $value = $line -replace ('^' + [regex]::Escape($Name) + '='), ''
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Missing environment value: $Name"
    }
    return $value
}

function Wait-HttpStatus {
    param([string]$Uri, [int]$ExpectedStatus, [int]$WaitSeconds)

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($WaitSeconds)
    do {
        try {
            $response = Invoke-WebRequest -Uri $Uri -TimeoutSec 3 -SkipHttpErrorCheck
            if ([int]$response.StatusCode -eq $ExpectedStatus) {
                return
            }
        }
        catch {
        }
        Start-Sleep -Milliseconds 500
    } while ([DateTimeOffset]::UtcNow -lt $deadline)
    throw "Timed out waiting for HTTP $ExpectedStatus from $Uri."
}

function Set-FaultMode {
    param([ValidateSet('ready', 'not_ready', 'timeout')][string]$Mode, [double]$DelaySeconds = 5)

    $body = @{ mode = $Mode; delay_seconds = $DelaySeconds } | ConvertTo-Json -Depth 4
    Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:$FaultRunnerPort/control" `
        -Headers $controlHeaders -ContentType 'application/json' -Body $body | Out-Null
}

function New-UniqueTestImage {
    param([string]$SourcePath)

    New-Item -ItemType Directory -Force -Path $generatedDirectory | Out-Null
    $destination = Join-Path $generatedDirectory ("retry-$([guid]::NewGuid()).jpg")
    $sourceBytes = [IO.File]::ReadAllBytes($SourcePath)
    $nonceBytes = [Text.Encoding]::ASCII.GetBytes("`nRETRY-E2E-$([guid]::NewGuid())")
    $combined = [byte[]]::new($sourceBytes.Length + $nonceBytes.Length)
    [Array]::Copy($sourceBytes, 0, $combined, 0, $sourceBytes.Length)
    [Array]::Copy($nonceBytes, 0, $combined, $sourceBytes.Length, $nonceBytes.Length)
    [IO.File]::WriteAllBytes($destination, $combined)
    return $destination
}

try {
    if ($ComposeProjectName -ne 'pig-inventory-p1-retry') {
        throw 'The retry E2E may only use the isolated pig-inventory-p1-retry Compose project.'
    }
    if (-not (Test-Path -LiteralPath $envFile -PathType Leaf)) {
        throw 'The local product .env file is missing.'
    }
    $resolvedImagePath = [IO.Path]::GetFullPath($ImagePath)
    if (-not (Test-Path -LiteralPath $resolvedImagePath -PathType Leaf)) {
        throw 'The E2E image was not found.'
    }

    $env:GATEWAY_PORT = $GatewayPort.ToString()
    $env:FAULT_INFERENCE_PORT = $InferencePort.ToString()
    $env:FAULT_RUNNER_CONTROL_PORT = $FaultRunnerPort.ToString()
    $env:FAULT_PROVIDER_TIMEOUT_SECONDS = '2'
    $env:FAULT_DELAY_SECONDS = '5'

    Invoke-RetryCompose -ComposeArguments @('up', '-d', '--build', 'redis', 'inference-fault-runner', 'inference-api', 'inference-worker')
    Wait-HttpStatus -Uri "http://127.0.0.1:$FaultRunnerPort/health/live" -ExpectedStatus 200 -WaitSeconds 60
    Set-FaultMode -Mode ready
    Wait-HttpStatus -Uri "http://127.0.0.1:$InferencePort/health/ready" -ExpectedStatus 200 -WaitSeconds 60
    Invoke-RetryCompose -ComposeArguments @('up', '-d', '--build')
    Wait-HttpStatus -Uri "http://127.0.0.1:$GatewayPort/actuator/health" -ExpectedStatus 200 -WaitSeconds $TimeoutSeconds

    Set-FaultMode -Mode timeout -DelaySeconds 5
    $testImage = New-UniqueTestImage -SourcePath $resolvedImagePath
    & (Join-Path $PSScriptRoot 'run-local-research-count-e2e.ps1') `
        -ComposeProjectName $ComposeProjectName `
        -BaseUrl "http://127.0.0.1:$GatewayPort/api/v1" `
        -ImagePath $testImage `
        -ExpectedFailureCode 'PROVIDER_TIMEOUT' `
        -TimeoutSeconds $TimeoutSeconds
    if (-not $?) {
        throw 'The initial failed inference scenario did not complete.'
    }

    $baseUrl = "http://127.0.0.1:$GatewayPort/api/v1"
    $password = Get-EnvValue -Name 'APP_E2E_FIXTURE_PASSWORD'
    $loginBody = @{ username = 'e2e-farm-admin'; password = $password } | ConvertTo-Json -Depth 4
    $login = Invoke-RestMethod -Method Post -Uri "$baseUrl/auth/login" `
        -Headers @{ 'X-Idempotency-Key' = [guid]::NewGuid().ToString() } `
        -ContentType 'application/json' -Body $loginBody
    $authHeaders = @{ Authorization = "Bearer $($login.accessToken)" }
    $failedJobs = @(Invoke-RestMethod -Uri "$baseUrl/inference-jobs/failed?limit=50" -Headers $authHeaders)
    if ($failedJobs.Count -ne 1 -or $failedJobs[0].failureCode -ne 'PROVIDER_TIMEOUT' -or -not $failedJobs[0].retryable) {
        throw 'The administrator failed-task query did not return the retryable timeout attempt.'
    }
    $source = $failedJobs[0]
    $retryKey = [guid]::NewGuid().ToString()
    $retryReason = 'Runner 已恢复，使用原媒体与模型身份执行管理员重试'
    $retryHeaders = @{ Authorization = "Bearer $($login.accessToken)"; 'X-Idempotency-Key' = $retryKey }
    $retryBody = @{ reason = $retryReason } | ConvertTo-Json -Depth 4
    $createdResponse = Invoke-WebRequest -Method Post -Uri "$baseUrl/inference-jobs/$($source.jobId)/retries" `
        -Headers $retryHeaders -ContentType 'application/json' -Body $retryBody
    $created = $createdResponse.Content | ConvertFrom-Json
    if ([int]$createdResponse.StatusCode -ne 201 -or $created.replayed -or $created.sourceJobId -ne $source.jobId) {
        throw 'The first retry request did not create the expected successor.'
    }
    $replayedResponse = Invoke-WebRequest -Method Post -Uri "$baseUrl/inference-jobs/$($source.jobId)/retries" `
        -Headers $retryHeaders -ContentType 'application/json' -Body $retryBody
    $replayed = $replayedResponse.Content | ConvertFrom-Json
    if ([int]$replayedResponse.StatusCode -ne 200 -or -not $replayed.replayed -or $replayed.retryJobId -ne $created.retryJobId) {
        throw 'The repeated retry intent did not return the same successor.'
    }
    $conflictHeaders = @{ Authorization = "Bearer $($login.accessToken)"; 'X-Idempotency-Key' = [guid]::NewGuid().ToString() }
    $conflict = Invoke-WebRequest -Method Post -Uri "$baseUrl/inference-jobs/$($source.jobId)/retries" `
        -Headers $conflictHeaders -ContentType 'application/json' -Body $retryBody -SkipHttpErrorCheck
    if ([int]$conflict.StatusCode -ne 409) {
        throw 'A second business intent against the same failed attempt was not rejected.'
    }

    $afterRetry = @(Invoke-RestMethod -Uri "$baseUrl/inference-jobs/failed?limit=50" -Headers $authHeaders)
    $preservedSource = @($afterRetry | Where-Object { $_.jobId -eq $source.jobId })
    if ($preservedSource.Count -ne 1 -or $preservedSource[0].retryable -or `
            $preservedSource[0].retriedByJobId -ne $created.retryJobId -or `
            $preservedSource[0].failureCode -ne 'PROVIDER_TIMEOUT') {
        throw 'The source failure was not preserved with the expected successor link.'
    }
    if ($created.requestedModel.checksum -ne $source.requestedModel.checksum) {
        throw 'The retry changed the requested model identity.'
    }

    Set-FaultMode -Mode ready
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    $session = $null
    do {
        $session = Invoke-RestMethod -Uri "$baseUrl/inventory-sessions/$($source.sessionId)" -Headers $authHeaders
        if ($session.inferenceStatus -eq 'review_required' -and $session.rawModelCount -eq 1) {
            break
        }
        Start-Sleep -Seconds 2
    } while ([DateTimeOffset]::UtcNow -lt $deadline)
    if ($null -eq $session -or $session.inferenceStatus -ne 'review_required' -or $session.rawModelCount -ne 1) {
        throw 'The successor inference task did not complete through Worker and Callback.'
    }
    if ($session.model.checksum -ne $source.requestedModel.checksum) {
        throw 'The completed successor stored a different model identity.'
    }
    $audit = @(Invoke-RestMethod -Uri "$baseUrl/audit-events?limit=30" -Headers $authHeaders)
    if (@($audit | Where-Object { $_.action -eq 'inference.retry_requested' -and $_.targetId -eq $source.jobId }).Count -ne 1) {
        throw 'The administrator retry AuditEvent was not visible exactly once.'
    }

    $summary = [ordered]@{
        completed_at = [DateTimeOffset]::UtcNow.ToString('o')
        compose_project = $ComposeProjectName
        source_failure = 'PROVIDER_TIMEOUT'
        retry_job_id = $created.retryJobId
        idempotent_replay = $true
        conflicting_second_intent = 'rejected'
        model_identity_preserved = $true
        worker_callback_recovery = 'passed'
        audit_event_count = 1
        data_classification = 'local ignored synthetic retry evidence'
    }
    $summaryPath = Join-Path $generatedDirectory 'inference-retry-e2e-summary.json'
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8
    Write-Output "[OK] Inference retry E2E passed. Summary: $summaryPath"
    $completed = $true
}
catch {
    Write-Error $_
    exit 1
}
finally {
    if ((-not $KeepStack) -and $completed) {
        Invoke-RetryCompose -ComposeArguments @('down')
    }
    elseif (-not $completed) {
        Write-Warning "Retry stack retained for diagnostics: $ComposeProjectName"
    }
}
