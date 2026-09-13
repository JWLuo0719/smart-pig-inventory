[CmdletBinding()]
param(
    [string]$ComposeProjectName = 'pig-inventory-p1-report-export',
    [int]$GatewayPort = 8092,
    [int]$TimeoutSeconds = 180,
    [switch]$KeepStack
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $repositoryRoot 'docker-compose.yml'
$faultComposeFile = Join-Path $repositoryRoot 'docker-compose.fault-e2e.yml'
$envFile = Join-Path $repositoryRoot '.env'
$generatedDirectory = Join-Path $repositoryRoot 'test-assets\generated'
$completed = $false

function Get-EnvValue {
    param([string]$Name)
    $pattern = '^' + [regex]::Escape($Name) + '=(.*)$'
    $line = Get-Content -LiteralPath $envFile | Where-Object { $_ -match $pattern } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($line)) { throw "Missing environment value: $Name" }
    $value = $line -replace ('^' + [regex]::Escape($Name) + '='), ''
    if ([string]::IsNullOrWhiteSpace($value)) { throw "Missing environment value: $Name" }
    return $value
}

function Invoke-ReportCompose {
    param([string[]]$ComposeArguments)
    & docker compose -p $ComposeProjectName -f $composeFile -f $faultComposeFile @ComposeArguments
    if ($LASTEXITCODE -ne 0) { throw "Docker Compose failed with exit code $LASTEXITCODE." }
}

function Wait-HttpStatus {
    param([string]$Uri, [int]$ExpectedStatus, [int]$WaitSeconds)
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($WaitSeconds)
    do {
        try {
            $response = Invoke-WebRequest -Uri $Uri -TimeoutSec 3 -SkipHttpErrorCheck
            if ([int]$response.StatusCode -eq $ExpectedStatus) { return }
        } catch {}
        Start-Sleep -Milliseconds 500
    } while ([DateTimeOffset]::UtcNow -lt $deadline)
    throw "Timed out waiting for HTTP $ExpectedStatus from $Uri."
}

try {
    if ($ComposeProjectName -ne 'pig-inventory-p1-report-export') {
        throw 'The report export E2E may only use the isolated pig-inventory-p1-report-export Compose project.'
    }
    if (-not (Test-Path -LiteralPath $envFile -PathType Leaf)) { throw 'The local product .env file is missing.' }
    $password = Get-EnvValue -Name 'APP_E2E_FIXTURE_PASSWORD'
    $primaryOrganizationCode = Get-EnvValue -Name 'APP_BOOTSTRAP_ORGANIZATION_CODE'
    if ($primaryOrganizationCode -notmatch '^[A-Za-z0-9_-]+$') { throw 'The local organization code is not safe for the isolated SQL fixture.' }

    $env:GATEWAY_PORT = $GatewayPort.ToString()
    $env:FAULT_INFERENCE_PORT = '18002'
    $env:FAULT_RUNNER_CONTROL_PORT = '19092'
    $env:SECURITY_ENABLED = 'true'
    $env:APP_E2E_FIXTURES_ENABLED = 'true'
    $env:INFERENCE_DISPATCHER_ENABLED = 'false'
    Invoke-ReportCompose -ComposeArguments @('up', '-d', '--build', 'redis', 'inference-fault-runner', 'inference-api', 'inference-worker')
    Wait-HttpStatus -Uri 'http://127.0.0.1:19092/health/live' -ExpectedStatus 200 -WaitSeconds 60
    $controlBody = @{ mode = 'ready'; delay_seconds = 0 } | ConvertTo-Json -Depth 3
    Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:19092/control' `
        -Headers @{ 'X-Fault-Control-Key' = 'local-e2e-only' } -ContentType 'application/json' -Body $controlBody | Out-Null
    Wait-HttpStatus -Uri 'http://127.0.0.1:18002/health/ready' -ExpectedStatus 200 -WaitSeconds 60
    Invoke-ReportCompose -ComposeArguments @('up', '-d', '--build')
    Wait-HttpStatus -Uri "http://127.0.0.1:$GatewayPort/actuator/health" -ExpectedStatus 200 -WaitSeconds $TimeoutSeconds

    $seedSql = @"
SET @primary_org = (SELECT id FROM farm_organization WHERE code = '$primaryOrganizationCode');
SET @primary_pen = (SELECT p.id FROM pen p JOIN building b ON b.id = p.building_id WHERE b.organization_id = @primary_org AND p.code = 'E2E-P01' LIMIT 1);
SET @secondary_org = (SELECT id FROM farm_organization WHERE code = 'E2E-SECOND');
SET @secondary_pen = (SELECT p.id FROM pen p JOIN building b ON b.id = p.building_id WHERE b.organization_id = @secondary_org AND p.code = 'E2E2-P01' LIMIT 1);
DELETE FROM inventory_session WHERE created_by IN ('e2e-seed', 'e2e-report-export');
INSERT INTO inventory_session (id, pen_id, business_date, status, confirmed_count, created_by, confirmed_by, confirmed_at)
VALUES (UUID_TO_BIN(UUID()), @primary_pen, '2026-09-01', 'confirmed', 17, 'e2e-report-export', 'e2e-reviewer', CURRENT_TIMESTAMP(6));
INSERT INTO inventory_session (id, pen_id, business_date, status, candidate_count, created_by)
VALUES (UUID_TO_BIN(UUID()), @primary_pen, '2026-09-01', 'review_required', 999, 'e2e-report-export');
INSERT INTO inventory_session (id, pen_id, business_date, status, confirmed_count, created_by, confirmed_by, confirmed_at)
VALUES (UUID_TO_BIN(UUID()), @secondary_pen, '2026-09-01', 'confirmed', 88, 'e2e-report-export', 'e2e-reviewer', CURRENT_TIMESTAMP(6));
"@
    $seedSql | docker compose -p $ComposeProjectName -f $composeFile exec -T mysql sh -lc 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"'
    if ($LASTEXITCODE -ne 0) { throw 'Failed to seed the isolated report export fixture.' }

    $baseUrl = "http://127.0.0.1:$GatewayPort/api/v1"
    $loginBody = @{ username = 'e2e-farm-admin'; password = $password } | ConvertTo-Json -Depth 4
    $login = Invoke-RestMethod -Method Post -Uri "$baseUrl/auth/login" `
        -Headers @{ 'X-Idempotency-Key' = [guid]::NewGuid().ToString() } `
        -ContentType 'application/json' -Body $loginBody
    $headers = @{ Authorization = "Bearer $($login.accessToken)" }
    New-Item -ItemType Directory -Force -Path $generatedDirectory | Out-Null
    $pdfPath = Join-Path $generatedDirectory 'report-export-e2e.pdf'
    $xlsxPath = Join-Path $generatedDirectory 'report-export-e2e.xlsx'
    $query = 'from=2026-09-01&to=2026-09-01'
    $pdf = Invoke-WebRequest -Uri "$baseUrl/inventory-reports/exports/pdf?$query" -Headers $headers -OutFile $pdfPath -PassThru
    $xlsx = Invoke-WebRequest -Uri "$baseUrl/inventory-reports/exports/xlsx?$query" -Headers $headers -OutFile $xlsxPath -PassThru
    if ([int]$pdf.StatusCode -ne 200 -or $pdf.Headers['Content-Type'] -notmatch '^application/pdf') {
        throw 'The PDF export response contract was not satisfied.'
    }
    if ([int]$xlsx.StatusCode -ne 200 -or $xlsx.Headers['Content-Type'] -notmatch 'spreadsheetml') {
        throw 'The XLSX export response contract was not satisfied.'
    }
    if ($pdf.Headers['Content-Disposition'] -notmatch 'pig-inventory-20260901-20260901.pdf') {
        throw 'The PDF Content-Disposition filename was not deterministic.'
    }
    if ($xlsx.Headers['Content-Disposition'] -notmatch 'pig-inventory-20260901-20260901.xlsx') {
        throw 'The XLSX Content-Disposition filename was not deterministic.'
    }
    $pdfBytes = [IO.File]::ReadAllBytes($pdfPath)
    $xlsxBytes = [IO.File]::ReadAllBytes($xlsxPath)
    if ([Text.Encoding]::ASCII.GetString($pdfBytes, 0, 4) -ne '%PDF') { throw 'The PDF payload signature is invalid.' }
    if ($xlsxBytes[0] -ne 0x50 -or $xlsxBytes[1] -ne 0x4B) { throw 'The XLSX payload signature is invalid.' }

    $badRange = Invoke-WebRequest -Uri "$baseUrl/inventory-reports/exports/pdf?from=2026-09-02&to=2026-09-01" `
        -Headers $headers -SkipHttpErrorCheck
    $badFormat = Invoke-WebRequest -Uri "$baseUrl/inventory-reports/exports/csv?$query" -Headers $headers -SkipHttpErrorCheck
    if ([int]$badRange.StatusCode -ne 422 -or [int]$badFormat.StatusCode -ne 422) {
        throw 'The export validation boundary did not return HTTP 422.'
    }

    $summary = [ordered]@{
        completed_at = [DateTimeOffset]::UtcNow.ToString('o')
        compose_project = $ComposeProjectName
        confirmed_primary_count = 17
        unconfirmed_candidate_excluded = 999
        second_organization_confirmed_excluded = 88
        pdf_status = [int]$pdf.StatusCode
        xlsx_status = [int]$xlsx.StatusCode
        invalid_range_status = [int]$badRange.StatusCode
        invalid_format_status = [int]$badFormat.StatusCode
        data_classification = 'local ignored synthetic confirmed-only report evidence'
    }
    $summaryPath = Join-Path $generatedDirectory 'report-export-e2e-summary.json'
    $summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding utf8
    Write-Output "[OK] Confirmed-only report export E2E passed. Summary: $summaryPath"
    $completed = $true
}
catch {
    Write-Error $_
    exit 1
}
finally {
    if ((-not $KeepStack) -and $completed) {
        Invoke-ReportCompose -ComposeArguments @('down')
    }
    elseif (-not $completed) {
        Write-Warning "Report export stack retained for diagnostics: $ComposeProjectName"
    }
}
