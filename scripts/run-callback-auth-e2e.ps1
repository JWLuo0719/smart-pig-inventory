#Requires -Version 7.0
[CmdletBinding()]
param([switch]$SkipBuild, [switch]$KeepStack)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $repositoryRoot 'test-assets/generated/callback-auth'
$project = 'pig-inventory-p0-callback-auth'
$composeArgs = @('-p', $project, '--env-file', (Join-Path $outputDirectory 'runtime.env'), '-f', (Join-Path $repositoryRoot 'docker-compose.yml'), '-f', (Join-Path $repositoryRoot 'docker-compose.callback-auth.yml'))
$completed = $false
$savedEnvironment = @{}

function Invoke-Compose([string[]]$Arguments) {
    & docker compose @composeArgs @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Callback-auth Compose failed: $($Arguments[0])" }
}
function Invoke-TestSql([string]$Sql) {
    $result = $Sql | & docker compose @composeArgs exec -T mysql sh -lc 'mysql -N -B -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"'
    if ($LASTEXITCODE -ne 0) { throw 'Callback-auth isolated SQL failed.' }
    return $result
}
function Invoke-Callback([string]$JobId, [string]$Key, [hashtable]$Payload, [int]$ExpectedStatus) {
    $headers = @{ 'X-Idempotency-Key' = $JobId }
    if ($Key) { $headers['X-Inference-Service-Key'] = $Key }
    $response = Invoke-WebRequest -Uri "http://127.0.0.1:8094/api/v1/inference-jobs/$JobId/result" -Method Put -Headers $headers -ContentType 'application/json' -Body ($Payload | ConvertTo-Json -Depth 8) -SkipHttpErrorCheck -TimeoutSec 15
    if ([int]$response.StatusCode -ne $ExpectedStatus) { throw "Expected callback HTTP $ExpectedStatus but received $($response.StatusCode)." }
    if ($ExpectedStatus -eq 401) {
        $content = if ($response.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($response.Content) } else { [string]$response.Content }
        if (($content | ConvertFrom-Json).code -ne 'INFERENCE_CALLBACK_UNAUTHORIZED') { throw 'Callback rejected by the wrong security boundary.' }
        if ($content.Contains('synthetic-callback-service-only')) { throw 'Callback response exposed a credential.' }
    }
}

try {
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
    $values = [ordered]@{
        MYSQL_DATABASE = 'pig_inventory'; MYSQL_USER = 'pig_inventory'; MYSQL_PASSWORD = 'synthetic-callback-mysql'
        MYSQL_ROOT_PASSWORD = 'synthetic-callback-root'; MINIO_ROOT_USER = 'callback-test'; MINIO_ROOT_PASSWORD = 'synthetic-callback-minio'; MINIO_BUCKET = 'pig-inventory'
        SECURITY_ENABLED = 'false'; SPRING_PROFILES_ACTIVE = 'dev'
        JWT_SIGNING_SECRET = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('synthetic-callback-signing-key-only-20260908'))
        APP_BOOTSTRAP_ADMIN_USERNAME = ''; APP_BOOTSTRAP_ADMIN_PASSWORD = ''; APP_BOOTSTRAP_ADMIN_DISPLAY_NAME = ''
        APP_BOOTSTRAP_ORGANIZATION_CODE = ''; APP_BOOTSTRAP_ORGANIZATION_NAME = ''; APP_E2E_FIXTURES_ENABLED = 'false'; APP_E2E_FIXTURE_PASSWORD = ''
        INFERENCE_CALLBACK_TOKEN = 'synthetic-callback-service-only'; INFERENCE_DISPATCHER_ENABLED = 'false'
        COUNTING_PROVIDER = 'unavailable'; MODEL_RESEARCH_ENABLED = 'false'; MODEL_APPROVED = 'false'
        MODEL_KEY = 'pending-license-review'; MODEL_VERSION = 'unverified'; MODEL_CHECKSUM = 'unverified'; MODEL_ADAPTER_VERSION = 'http-v1'
        MULTIVIEW_AUTO_COUNT_ENABLED = 'false'; YOLO_HTTP_ENDPOINT = ''; YOLO_HTTP_READY_ENDPOINT = ''
    }
    foreach ($name in $values.Keys) {
        $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, [string]$values[$name], 'Process')
    }
    $values.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } | Set-Content -LiteralPath (Join-Path $outputDirectory 'runtime.env') -Encoding utf8
    Invoke-Compose @('config', '--quiet')
    if (-not $SkipBuild) { Invoke-Compose @('build', 'business-api', 'inference-api') }
    $results = @()
    foreach ($securityMode in @('false', 'true')) {
        $env:SECURITY_ENABLED = $securityMode
        Invoke-Compose @('up', '-d', '--wait', '--wait-timeout', '240', 'business-api')
        $orgId = [guid]::NewGuid().ToString(); $buildingId = [guid]::NewGuid().ToString(); $penId = [guid]::NewGuid().ToString()
        $sessionId = [guid]::NewGuid().ToString(); $packageId = [guid]::NewGuid().ToString(); $captureId = [guid]::NewGuid().ToString(); $jobId = [guid]::NewGuid().ToString()
        # Callback-only synthetic fixture; no images, weights or historical rows are altered.
        Invoke-TestSql @"
START TRANSACTION;
INSERT INTO farm_organization (id, code, name) VALUES (UUID_TO_BIN('$orgId'), '$orgId', 'Synthetic callback-auth fixture');
INSERT INTO building (id, organization_id, code, name) VALUES (UUID_TO_BIN('$buildingId'), UUID_TO_BIN('$orgId'), 'B01', 'Synthetic building');
INSERT INTO pen (id, building_id, code, name) VALUES (UUID_TO_BIN('$penId'), UUID_TO_BIN('$buildingId'), 'P01', 'Synthetic pen');
INSERT INTO inventory_session (id, pen_id, business_date, status, created_by) VALUES (UUID_TO_BIN('$sessionId'), UUID_TO_BIN('$penId'), CURRENT_DATE(), 'submitted', 'synthetic-callback-auth');
INSERT INTO upload_package (id, organization_id, pen_id, session_id, client_package_id, business_date, capture_kind, idempotency_key, state)
VALUES (UUID_TO_BIN('$packageId'), UUID_TO_BIN('$orgId'), UUID_TO_BIN('$penId'), UUID_TO_BIN('$sessionId'), UUID_TO_BIN('$packageId'), CURRENT_DATE(), 'single', '$packageId', 'committed');
INSERT INTO capture_set (id, session_id, upload_package_id, client_capture_id, kind) VALUES (UUID_TO_BIN('$captureId'), UUID_TO_BIN('$sessionId'), UUID_TO_BIN('$packageId'), UUID_TO_BIN('$captureId'), 'single');
INSERT INTO inference_job (id, root_job_id, session_id, capture_set_id, status, provider_key, correlation_id) VALUES (UUID_TO_BIN('$jobId'), UUID_TO_BIN('$jobId'), UUID_TO_BIN('$sessionId'), UUID_TO_BIN('$captureId'), 'submitted', 'unavailable', 'synthetic-callback-auth');
COMMIT;
"@ | Out-Null
        $payload = @{ status = 'review_required'; count = $null; detections = @(); warnings = @('Synthetic callback-auth fixture'); modelKey = 'pending-license-review'; modelVersion = 'unverified'; modelChecksum = 'unverified'; adapterVersion = 'http-v1'; inferenceSource = 'unavailable'; latencyMs = 0 }
        Invoke-Callback $jobId '' $payload 401
        Invoke-Callback $jobId 'wrong-service-key' $payload 401
        $before = Invoke-TestSql "SELECT CONCAT(j.status, ':', (SELECT COUNT(*) FROM inference_result_receipt r WHERE r.inference_job_id = j.id), ':', s.status) FROM inference_job j JOIN inventory_session s ON s.id = j.session_id WHERE j.id = UUID_TO_BIN('$jobId');"
        if ($before -ne 'submitted:0:submitted') { throw 'Rejected callback changed persistent state.' }
        Invoke-Callback $jobId $values.INFERENCE_CALLBACK_TOKEN $payload 204
        Invoke-Callback $jobId $values.INFERENCE_CALLBACK_TOKEN $payload 200
        $payload.warnings = @('Different final result must conflict')
        Invoke-Callback $jobId $values.INFERENCE_CALLBACK_TOKEN $payload 409
        $after = Invoke-TestSql "SELECT CONCAT(j.status, ':', (SELECT COUNT(*) FROM inference_result_receipt r WHERE r.inference_job_id = j.id), ':', (SELECT COUNT(*) FROM count_result c WHERE c.inference_job_id = j.id), ':', s.status, ':', COALESCE(s.confirmed_count, 'NULL')) FROM inference_job j JOIN inventory_session s ON s.id = j.session_id WHERE j.id = UUID_TO_BIN('$jobId');"
        if ($after -ne 'review_required:1:1:review_required:NULL') { throw 'Authenticated callback did not preserve the terminal result and replay invariants.' }
        $results += @{ end_user_security = $securityMode; missing_key = 401; wrong_key = 401; first_valid = 204; replay = 200; conflicting_result = 409; rejected_state_unchanged = $true; result_rows = 1; receipt_rows = 1; confirmed_count = $null }
        Write-Output "[OK] Callback boundary passed with end-user security=$securityMode."
    }
    # An unconfigured callback credential must remain fail-closed even with dispatcher/login off.
    $env:SECURITY_ENABLED = 'false'
    $env:INFERENCE_CALLBACK_TOKEN = ''
    Invoke-Compose @('up', '-d', '--wait', '--wait-timeout', '240', 'business-api')
    Invoke-Callback $jobId '' $payload 401
    Invoke-Callback $jobId $values.INFERENCE_CALLBACK_TOKEN $payload 401
    $summary = @{ status = 'passed'; completed_at = [DateTimeOffset]::UtcNow.ToString('o'); compose_project = $project; modes = $results; unconfigured_key_rejected = $true; data_classification = 'synthetic callback-only fixture; no model or image validation'; human_acceptance = 'pending' }
    $summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $outputDirectory 'summary.json') -Encoding utf8
    $completed = $true
    Write-Output '[OK] Callback-auth HTTP and MySQL semantic regression passed.'
} finally {
    try {
        if ($completed -and (-not $KeepStack)) { Invoke-Compose @('down') }
        if (-not $completed) { Write-Warning "Retained isolated stack for diagnostics: $project" }
    } finally {
        foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process') }
    }
}
