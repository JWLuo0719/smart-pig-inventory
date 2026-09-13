#Requires -Version 7.0
[CmdletBinding()]
param([switch]$SkipBuild, [switch]$KeepStack)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $repositoryRoot 'test-assets/generated/observability'
$project = 'pig-inventory-p0-observability'
$composeArgs = @('-p', $project, '--env-file', (Join-Path $outputDirectory 'runtime.env'), '-f', (Join-Path $repositoryRoot 'docker-compose.yml'), '-f', (Join-Path $repositoryRoot 'docker-compose.observability.yml'))
$completed = $false
$savedEnvironment = @{}
function Invoke-Compose([string[]]$Arguments) {
    & docker compose @composeArgs @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Observability Compose failed: $($Arguments[0])" }
}
function Invoke-Sql([string]$Sql) {
    $Sql | & docker compose @composeArgs exec -T mysql sh -lc 'mysql -N -B -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"'
    if ($LASTEXITCODE -ne 0) { throw 'Isolated SQL failed.' }
}
function Invoke-Http([string]$Path, [string]$Method = 'GET', $Body = $null, [hashtable]$Headers = @{}, [int]$Expected = 200) {
    $params = @{ Uri = "http://127.0.0.1:8095/$Path"; Method = $Method; Headers = $Headers; SkipHttpErrorCheck = $true; TimeoutSec = 15 }
    if ($null -ne $Body) { $params.ContentType = 'application/json'; $params.Body = $Body | ConvertTo-Json -Depth 12 }
    $response = Invoke-WebRequest @params
    if ([int]$response.StatusCode -ne $Expected) { throw "Unexpected HTTP status on $Path : $($response.StatusCode), expected $Expected" }
    $text = if ($response.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($response.Content) } else { [string]$response.Content }
    return $text
}
function Read-Metrics {
    Invoke-Http 'actuator/prometheus' -Headers @{ 'X-Monitoring-Service-Key' = 'synthetic-metrics-key' }
}
function Metric([string]$Text, [string]$Name) {
    $match = [regex]::Match($Text, "(?m)^$Name ([^\r\n]+)")
    if (-not $match.Success) { throw "Missing metric: $Name" }
    return [double]::Parse($match.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture)
}
function Await-Metric([string]$Name, [double]$Expected) {
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(30)
    do {
        $metrics = Read-Metrics
        if ((Metric $metrics $Name) -eq $Expected) { return $metrics }
        Start-Sleep -Milliseconds 500
    } while ([DateTimeOffset]::UtcNow -lt $deadline)
    throw "Metric did not converge: $Name"
}
try {
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
    $values = [ordered]@{
        MYSQL_DATABASE='pig_inventory'; MYSQL_USER='pig_inventory'; MYSQL_PASSWORD='synthetic-metrics-mysql'; MYSQL_ROOT_PASSWORD='synthetic-metrics-root'
        MINIO_ROOT_USER='metrics-test'; MINIO_ROOT_PASSWORD='synthetic-metrics-minio'; MINIO_BUCKET='pig-inventory'
        SECURITY_ENABLED='false'; SPRING_PROFILES_ACTIVE='dev'; JWT_SIGNING_SECRET=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('synthetic-observability-signing-key-20260908'))
        APP_BOOTSTRAP_ADMIN_USERNAME=''; APP_BOOTSTRAP_ADMIN_PASSWORD=''; APP_BOOTSTRAP_ADMIN_DISPLAY_NAME=''; APP_BOOTSTRAP_ORGANIZATION_CODE=''; APP_BOOTSTRAP_ORGANIZATION_NAME=''; APP_E2E_FIXTURES_ENABLED='false'; APP_E2E_FIXTURE_PASSWORD=''
        MONITORING_SERVICE_KEY='synthetic-metrics-key'; METRICS_SNAPSHOT_DELAY_MS='1000'
        INFERENCE_CALLBACK_TOKEN='synthetic-metrics-callback'; INFERENCE_DISPATCHER_ENABLED='false'; COUNTING_PROVIDER='unavailable'; MODEL_RESEARCH_ENABLED='false'; MODEL_APPROVED='false'
        MODEL_KEY='pending-license-review'; MODEL_VERSION='unverified'; MODEL_CHECKSUM='unverified'; MODEL_ADAPTER_VERSION='http-v1'; MULTIVIEW_AUTO_COUNT_ENABLED='false'; YOLO_HTTP_ENDPOINT=''; YOLO_HTTP_READY_ENDPOINT=''
    }
    foreach ($name in $values.Keys) {
        $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, [string]$values[$name], 'Process')
    }
    $values.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } | Set-Content -LiteralPath (Join-Path $outputDirectory 'runtime.env') -Encoding utf8
    Invoke-Compose @('config','--quiet')
    Invoke-Compose @('run','--rm','--no-deps','promtool','check','rules','/rules/business-rules.yml')
    Invoke-Compose @('run','--rm','--no-deps','promtool','test','rules','/rules/business-rules.test.yml')
    if (-not $SkipBuild) { Invoke-Compose @('build','business-api','inference-api') }
    Invoke-Compose @('up','-d','--wait','--wait-timeout','240','business-api')
    $before = Await-Metric 'pig_metrics_snapshot_available' 1
    $org = [guid]::NewGuid().ToString(); $building = [guid]::NewGuid().ToString(); $pen = [guid]::NewGuid().ToString()
    Invoke-Sql @"
INSERT INTO farm_organization (id,code,name) VALUES (UUID_TO_BIN('$org'),'$org','Synthetic observability');
INSERT INTO building (id,organization_id,code,name) VALUES (UUID_TO_BIN('$building'),UUID_TO_BIN('$org'),'B01','Synthetic');
INSERT INTO pen (id,building_id,code,name) VALUES (UUID_TO_BIN('$pen'),UUID_TO_BIN('$building'),'P01','Synthetic');
"@ | Out-Null
    # Security is off only in this isolated upload fixture; metrics remain independently protected.
    $date = Get-Date -Format yyyy-MM-dd
    $key = @{ 'X-Idempotency-Key' = [guid]::NewGuid().ToString() }
    $body = @{ clientPackageId=[guid]::NewGuid().ToString(); organizationId=$org; penId=$pen; businessDate=$date; captureKind='single' }
    $package = (Invoke-Http 'api/v1/upload-packages' POST $body $key 201) | ConvertFrom-Json
    Invoke-Http 'api/v1/upload-packages' POST $body $key 200 | Out-Null
    $packagePath = "api/v1/upload-packages/$($package.id)"
    $asset = [guid]::NewGuid().ToString()
    $bytes = [Text.Encoding]::ASCII.GetBytes("synthetic-metric-blob-$asset")
    $sha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    $blobResponse = Invoke-WebRequest -Uri "http://127.0.0.1:8095/$packagePath/blobs/$asset" -Method Put -ContentType 'application/octet-stream' -Body $bytes -Headers @{ 'X-Idempotency-Key'=$key['X-Idempotency-Key']; 'X-Content-SHA256'=$sha }
    if ($blobResponse.StatusCode -ne 201) { throw 'Blob fixture failed.' }
    $manifest = @{ captureSetId=[guid]::NewGuid().ToString(); captureKind='single'; penId=$pen; assets=@(@{ assetId=$asset; viewPosition='single'; capturedAt=[DateTimeOffset]::UtcNow.ToString('o'); originalName='synthetic-not-an-image.bin'; width=1; height=1; sha256=$sha; byteSize=$bytes.Length; mediaType='image/png'; exif=@{}; roi=$null }) }
    Invoke-Http "$packagePath/manifest" PUT $manifest $key 201 | Out-Null
    $commit = (Invoke-Http "$packagePath/commit" POST $null $key 201) | ConvertFrom-Json
    Invoke-Http "$packagePath/commit" POST $null $key 200 | Out-Null
    # A second upload of the same bytes must be rejected by the actual manifest rule.
    $duplicateKey = @{ 'X-Idempotency-Key'=[guid]::NewGuid().ToString() }
    $body.clientPackageId = [guid]::NewGuid().ToString()
    $duplicatePackage = (Invoke-Http 'api/v1/upload-packages' POST $body $duplicateKey 201) | ConvertFrom-Json
    $duplicateAsset = [guid]::NewGuid().ToString()
    Invoke-WebRequest -Uri "http://127.0.0.1:8095/api/v1/upload-packages/$($duplicatePackage.id)/blobs/$duplicateAsset" -Method Put -ContentType 'application/octet-stream' -Body $bytes -Headers @{ 'X-Idempotency-Key'=$duplicateKey['X-Idempotency-Key']; 'X-Content-SHA256'=$sha } | Out-Null
    $manifest.captureSetId = [guid]::NewGuid().ToString()
    $manifest.assets[0].assetId = $duplicateAsset
    Invoke-Http "api/v1/upload-packages/$($duplicatePackage.id)/manifest" PUT $manifest $duplicateKey 409 | Out-Null
    if ((Metric (Read-Metrics) 'pig_upload_duplicate_rejections_total') -ne ((Metric $before 'pig_upload_duplicate_rejections_total') + 1)) { throw 'Duplicate rejection counter did not increment.' }
    $payload = @{ status='failed'; count=$null; detections=@(); warnings=@(); modelKey='pending-license-review'; modelVersion='unverified'; modelChecksum='unverified'; adapterVersion='http-v1'; inferenceSource='synthetic'; latencyMs=1250; failureCode='PROVIDER_TIMEOUT'; failureMessage='Synthetic timeout' }
    $callbackHeaders = @{ 'X-Inference-Service-Key'='synthetic-metrics-callback'; 'X-Idempotency-Key'=$key['X-Idempotency-Key'] }
    Invoke-Http "api/v1/inference-jobs/$($commit.inferenceJobId)/result" PUT $payload $callbackHeaders 204 | Out-Null
    Invoke-Http "api/v1/inference-jobs/$($commit.inferenceJobId)/result" PUT $payload $callbackHeaders 200 | Out-Null
    $after = Await-Metric 'pig_inference_results_failed_last24h' ((Metric $before 'pig_inference_results_failed_last24h') + 1)
    if ((Metric $after 'pig_inference_latency_failed_seconds_last24h') -ne ((Metric $before 'pig_inference_latency_failed_seconds_last24h') + 1.25)) { throw 'Callback replay inflated latency.' }
    Invoke-Http "api/v1/inference-jobs/$($commit.inferenceJobId)/retries" POST @{reason='Synthetic metric retry verification'} $key 201 | Out-Null
    Invoke-Http "api/v1/inference-jobs/$($commit.inferenceJobId)/retries" POST @{reason='Synthetic metric retry verification'} $key 200 | Out-Null
    $after = Await-Metric 'pig_inference_retries_last24h' ((Metric $before 'pig_inference_retries_last24h') + 1)
    foreach ($outcome in @('created','replayed')) {
        $counter = 'pig_upload_requests_total\{outcome="' + $outcome + '",step="commit"\}'
        if ((Metric $after $counter) -ne ((Metric $before $counter) + 1)) { throw 'Commit request delta is incorrect.' }
    }
    if ($after.Contains($org) -or $after.Contains($asset) -or $after.Contains('synthetic-metrics-key')) { throw 'Metrics exposed identity or secret.' }
    Await-Metric 'pig_inventory_review_pending' ((Metric $before 'pig_inventory_review_pending') + 1) | Out-Null
    Invoke-Http "api/v1/inventory-sessions/$($commit.sessionId)/confirm" POST @{confirmedCount=17;reason='Synthetic metric confirmation'} $key | Out-Null
    Invoke-Http "api/v1/inventory-sessions/$($commit.sessionId)/corrections" POST @{correctedCount=19;reason='Synthetic metric correction'} $key | Out-Null
    $after = Await-Metric 'pig_inventory_review_completed_last24h' ((Metric $before 'pig_inventory_review_completed_last24h') + 1)
    Await-Metric 'pig_inventory_review_pending' (Metric $before 'pig_inventory_review_pending') | Out-Null
    Await-Metric 'pig_inference_jobs_outstanding' ((Metric $before 'pig_inference_jobs_outstanding') + 1) | Out-Null
    Await-Metric 'pig_inference_outbox_pending' ((Metric $before 'pig_inference_outbox_pending') + 2) | Out-Null
    # Verify every endpoint and both end-user security modes with actual HTTP.
    foreach ($mode in @('false','true')) {
        $env:SECURITY_ENABLED = $mode
        Invoke-Compose @('up','-d','--wait','--wait-timeout','240','business-api')
        foreach ($path in @('actuator/prometheus','actuator/metrics','actuator/metrics/pig.inventory.review.pending')) {
            Invoke-Http $path -Expected 401 | Out-Null
            Invoke-Http $path -Headers @{ 'X-Monitoring-Service-Key'='wrong' } -Expected 401 | Out-Null
            Invoke-Http $path -Headers @{ 'X-Monitoring-Service-Key'='synthetic-metrics-key' } | Out-Null
        }
    }
    $env:MONITORING_SERVICE_KEY = ''
    $env:SECURITY_ENABLED = 'false'
    Invoke-Compose @('up','-d','--wait','--wait-timeout','240','business-api')
    Invoke-Http 'actuator/prometheus' -Headers @{ 'X-Monitoring-Service-Key'='synthetic-metrics-key' } -Expected 401 | Out-Null
    @{ status='passed'; completed_at=[DateTimeOffset]::UtcNow.ToString('o'); compose_project=$project; rules='promtool passed'; upload_new_and_replay=$true; duplicate_rejection=$true; callback_and_retry_not_inflated=$true; correction_not_inflated=$true; queue_deltas=$true; latency_seconds=1.25; metrics_independent_auth=$true; no_identity_labels=$true; human_acceptance='pending'; fixture='synthetic bytes, no image decoding or worker inference claimed' } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $outputDirectory 'summary.json') -Encoding utf8
    $completed = $true
    Write-Output '[OK] Observability HTTP, database and local rules passed.'
} finally {
    try {
        if ($completed -and (-not $KeepStack)) { Invoke-Compose @('down') }
        if (-not $completed) { Write-Warning "Retained isolated stack: $project" }
    } finally {
        foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process') }
    }
}
