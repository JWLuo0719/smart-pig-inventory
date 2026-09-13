#Requires -Version 7.0
[CmdletBinding()]
param([switch]$SkipBuild, [switch]$KeepStack)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$project = 'pig-inventory-p0-admin-runtime'
$outputDirectory = Join-Path $repositoryRoot 'test-assets/generated/admin-runtime'
$composeFiles = @('-p', $project, '--env-file', (Join-Path $outputDirectory 'runtime.env'), '-f', (Join-Path $repositoryRoot 'docker-compose.yml'), '-f', (Join-Path $repositoryRoot 'docker-compose.admin-runtime.yml'))
$completed = $false
$browserOpened = $false
$savedEnvironment = @{}
function Invoke-Compose([string[]]$Arguments) {
    & docker compose @composeFiles @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Isolated Compose failed: $($Arguments[0])" }
}
function Invoke-Api([string]$Path, [string]$Method = 'GET', $Body = $null, [string]$Token = '') {
    $headers = @{ 'X-Idempotency-Key' = [guid]::NewGuid().ToString() }
    if ($Token) { $headers.Authorization = "Bearer $Token" }
    $prefix = if ($Path.StartsWith('upload-packages')) { 'v1' } else { 'backend' }
    $args = @{ Uri = "http://127.0.0.1:8093/api/$prefix/$Path"; Method = $Method; Headers = $headers; TimeoutSec = 20 }
    if ($null -ne $Body) { $args.ContentType = 'application/json'; $args.Body = $Body | ConvertTo-Json -Depth 12 }
    Invoke-RestMethod @args
}
function Get-Login {
    Invoke-Api -Path 'auth/login' -Method POST -Body @{ username = 'e2e-farm-admin'; password = 'synthetic-admin-runtime-only-2026' }
}
try {
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
    # Test-only credentials, no product .env or user browser profile is read.
    $values = [ordered]@{
        MYSQL_DATABASE = 'pig_inventory'; MYSQL_USER = 'pig_inventory'; MYSQL_PASSWORD = 'synthetic-runtime-mysql'
        MYSQL_ROOT_PASSWORD = 'synthetic-runtime-root'; MINIO_ROOT_USER = 'runtime-test'; MINIO_ROOT_PASSWORD = 'synthetic-runtime-minio'
        MINIO_BUCKET = 'pig-inventory'; SECURITY_ENABLED = 'true'; SPRING_PROFILES_ACTIVE = 'dev'
        JWT_SIGNING_SECRET = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('synthetic-runtime-signing-key-only-20260908'))
        APP_BOOTSTRAP_ADMIN_USERNAME = 'runtime-bootstrap'; APP_BOOTSTRAP_ADMIN_PASSWORD = 'synthetic-bootstrap-only-2026'
        APP_BOOTSTRAP_ADMIN_DISPLAY_NAME = 'Synthetic runtime admin'; APP_BOOTSTRAP_ORGANIZATION_CODE = 'ADMIN-RUNTIME'
        APP_BOOTSTRAP_ORGANIZATION_NAME = 'Synthetic runtime organization'; APP_E2E_FIXTURES_ENABLED = 'true'
        APP_E2E_FIXTURE_PASSWORD = 'synthetic-admin-runtime-only-2026'; INFERENCE_CALLBACK_TOKEN = 'synthetic-runtime-callback-only'
        INFERENCE_DISPATCHER_ENABLED = 'false'; COUNTING_PROVIDER = 'unavailable'; MODEL_RESEARCH_ENABLED = 'false'; MODEL_APPROVED = 'false'
        MODEL_KEY = 'pending-license-review'; MODEL_VERSION = 'unverified'; MODEL_CHECKSUM = 'unverified'; MODEL_ADAPTER_VERSION = 'http-v1'
        MULTIVIEW_AUTO_COUNT_ENABLED = 'false'; YOLO_HTTP_ENDPOINT = ''; YOLO_HTTP_READY_ENDPOINT = ''
    }
    foreach ($name in $values.Keys) {
        $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, [string]$values[$name], 'Process')
    }
    $values.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } | Set-Content -LiteralPath (Join-Path $outputDirectory 'runtime.env') -Encoding utf8
    Invoke-Compose @('config', '--quiet')
    $up = @('up', '-d', '--wait', '--wait-timeout', '240')
    if (-not $SkipBuild) { $up += '--build' }
    Invoke-Compose $up

    $runId = [guid]::NewGuid().ToString('N')
    $buildingId = [guid]::NewGuid().ToString()
    $sourcePen = [guid]::NewGuid().ToString()
    $failedPen = [guid]::NewGuid().ToString()
    $seed = @"
SET @org = (SELECT id FROM farm_organization WHERE code = 'ADMIN-RUNTIME');
INSERT INTO building (id, organization_id, code, name) VALUES (UUID_TO_BIN('$buildingId'), @org, 'RT-$runId', 'Synthetic runtime building');
INSERT INTO pen (id, building_id, code, name) VALUES
 (UUID_TO_BIN('$sourcePen'), UUID_TO_BIN('$buildingId'), 'CONF-$runId', 'Synthetic correction pen'),
 (UUID_TO_BIN('$failedPen'), UUID_TO_BIN('$buildingId'), 'FAIL-$runId', 'Synthetic failure pen');
"@
    $seed | & docker compose @composeFiles exec -T mysql sh -lc 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"'
    if ($LASTEXITCODE -ne 0) { throw 'Synthetic fixture seed failed.' }
    $login = Get-Login
    $me = Invoke-Api 'me' -Token $login.accessToken
    $date = Get-Date -Format 'yyyy-MM-dd'
    $sessions = @()
    foreach ($penId in @($sourcePen, $failedPen)) {
        # Generated 1x1 PNG with a unique trailing synthetic tag; no research/production images.
        $png = [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=')
        $bytes = [byte[]]($png + [Text.Encoding]::ASCII.GetBytes([guid]::NewGuid().ToString()))
        $sha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
        $login = Get-Login
        $package = Invoke-Api 'upload-packages' POST @{ clientPackageId = [guid]::NewGuid().ToString(); organizationId = $me.activeOrganizationId; penId = $penId; businessDate = $date; captureKind = 'single' } $login.accessToken
        $assetId = [guid]::NewGuid().ToString()
        $packageId = $package.id
        # Upload endpoints are intentionally not admitted by the admin proxy.
        Invoke-WebRequest -Uri "http://127.0.0.1:8093/api/v1/upload-packages/$packageId/blobs/$assetId" -Method Put -Headers @{ Authorization = "Bearer $($login.accessToken)"; 'X-Idempotency-Key' = [guid]::NewGuid().ToString(); 'X-Content-SHA256' = $sha } -ContentType 'application/octet-stream' -Body $bytes | Out-Null
        $manifest = @{ captureSetId = [guid]::NewGuid().ToString(); captureKind = 'single'; penId = $penId; assets = @(@{ assetId = $assetId; viewPosition = 'single'; capturedAt = [DateTimeOffset]::UtcNow.ToString('o'); originalName = 'synthetic.png'; width = 1; height = 1; sha256 = $sha; perceptualHash = $null; byteSize = $bytes.Length; mediaType = 'image/png'; exif = @{}; roi = $null }) }
        $headers = @{ Authorization = "Bearer $($login.accessToken)"; 'X-Idempotency-Key' = [guid]::NewGuid().ToString() }
        Invoke-RestMethod -Uri "http://127.0.0.1:8093/api/v1/upload-packages/$packageId/manifest" -Method Put -Headers $headers -ContentType 'application/json' -Body ($manifest | ConvertTo-Json -Depth 12) | Out-Null
        $commit = Invoke-RestMethod -Uri "http://127.0.0.1:8093/api/v1/upload-packages/$packageId/commit" -Method Post -Headers $headers
        $sessions += $commit
        # Seed a terminal failure through the authenticated callback contract.
        # Worker/provider behavior is covered by the separate fault E2E, not this browser test.
        $callback = @{ status = 'failed'; count = $null; detections = @(); warnings = @('Synthetic admin runtime fixture'); modelKey = 'pending-license-review'; modelVersion = 'unverified'; modelChecksum = 'unverified'; adapterVersion = 'http-v1'; inferenceSource = 'synthetic-runtime'; latencyMs = 0; failureCode = 'PROVIDER_TIMEOUT'; failureMessage = 'Synthetic admin runtime timeout fixture' }
        $jobId = $commit.inferenceJobId
        Invoke-WebRequest -Uri "http://127.0.0.1:8093/api/v1/inference-jobs/$jobId/result" -Method Put -Headers @{ 'X-Inference-Service-Key' = $values.INFERENCE_CALLBACK_TOKEN; 'X-Idempotency-Key' = [guid]::NewGuid().ToString() } -ContentType 'application/json' -Body ($callback | ConvertTo-Json -Depth 8) | Out-Null
    }
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(120)
    do {
        $login = Get-Login
        $failed = Invoke-Api 'inference-jobs/failed?limit=100' -Token $login.accessToken
        $ready = @($failed | Where-Object { $_.sessionId -in $sessions.sessionId }).Count -eq 2
        if ($ready) { break }
        Start-Sleep -Seconds 1
    } while ([DateTimeOffset]::UtcNow -lt $deadline)
    if (-not $ready) { throw 'Synthetic failure callbacks did not reach the administrator query.' }
    $sourceId = $sessions[0].sessionId
    Invoke-Api "inventory-sessions/$sourceId/confirm" POST @{ confirmedCount = 17; reason = 'Synthetic runtime initial confirmation' } $login.accessToken | Out-Null
    $config = @{ baseUrl = 'http://127.0.0.1:8093'; password = $values.APP_E2E_FIXTURE_PASSWORD; sourceId = $sourceId; sourcePen = $sourcePen; sourceCode = "CONF-$runId"; failedJobId = $sessions[1].inferenceJobId; date = $date }
    $template = Get-Content -LiteralPath (Join-Path $repositoryRoot 'test-support/admin-runtime/browser-regression.js') -Raw
    $runnerPath = Join-Path $outputDirectory 'browser-run.js'
    $template.Replace('__RUNTIME_CONFIG__', ($config | ConvertTo-Json -Depth 6 -Compress)) | Set-Content -LiteralPath $runnerPath -Encoding utf8
    Push-Location $outputDirectory
    try {
        & npx --yes --package @playwright/cli@0.1.19 playwright-cli -s=admin-runtime-e2e open $config.baseUrl --browser msedge
        if ($LASTEXITCODE -ne 0) { throw 'Browser runtime preflight failed.' }
        $browserOpened = $true
        $raw = & npx --yes --package @playwright/cli@0.1.19 playwright-cli -s=admin-runtime-e2e run-code --filename $runnerPath --json
        $cliExit = $LASTEXITCODE
        $raw | Set-Content -LiteralPath (Join-Path $outputDirectory 'browser-result.json') -Encoding utf8
        if ($cliExit -ne 0) { throw 'Browser CLI failed; inspect ignored browser-result.json.' }
        $cli = ($raw -join "`n") | ConvertFrom-Json
        if (-not $cli.PSObject.Properties['result']) {
            # The CLI may yield on a native prompt before the snippet finishes.
            # A zero exit code or empty object is never sufficient evidence.
            $readback = 'async (page) => { await page.waitForFunction(() => window.__adminRuntimeResult, null, { timeout: 120000 }); return page.evaluate(() => window.__adminRuntimeResult); }'
            $raw = & npx --yes --package @playwright/cli@0.1.19 playwright-cli -s=admin-runtime-e2e run-code $readback --json
            $raw | Set-Content -LiteralPath (Join-Path $outputDirectory 'browser-result.json') -Encoding utf8
            if ($LASTEXITCODE -ne 0) { throw 'Browser completion readback failed.' }
            $cli = ($raw -join "`n") | ConvertFrom-Json
        }
        if (-not $cli.PSObject.Properties['result']) { throw 'Browser regression failed; inspect ignored browser-result.json.' }
        $result = $cli.result | ConvertFrom-Json
        if ($result.status -ne 'passed') { throw 'Browser semantic assertions did not pass.' }
        $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $outputDirectory 'summary.json') -Encoding utf8
    } finally { Pop-Location }
    $completed = $true
    Write-Output '[OK] Isolated admin browser/HTTP runtime regression passed.'
} finally {
    if ($browserOpened) {
        Push-Location $outputDirectory
        try { & npx --yes --package @playwright/cli@0.1.19 playwright-cli -s=admin-runtime-e2e close } finally { Pop-Location }
    }
    if ($completed -and (-not $KeepStack)) { Invoke-Compose @('down') }
    if (-not $completed) { Write-Warning "Retained isolated stack for diagnostics: $project" }
    foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process') }
}
