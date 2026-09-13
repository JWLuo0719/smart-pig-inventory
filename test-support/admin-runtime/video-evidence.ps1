#Requires -Version 7.0
# Run only after the fixed admin runtime stack is ready. Uses generated media, never P0.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$output = Join-Path $root 'test-assets/generated/admin-runtime'
$fixture = Join-Path $output 'video-evidence.mp4'
if (-not (Test-Path -LiteralPath $fixture)) { throw 'Generate the synthetic video fixture first.' }
$project = & docker inspect pig-inventory-p0-admin-runtime-business-api-1 --format '{{index .Config.Labels "com.docker.compose.project"}}'
if ($LASTEXITCODE -ne 0 -or $project -ne 'pig-inventory-p0-admin-runtime') { throw 'Wrong runtime project.' }
$base = 'http://127.0.0.1:8093/api/v1'
$script:token = ''
function Call-Api([string]$Path, [string]$Method='GET', $Body=$null) {
    $headers = @{ 'X-Idempotency-Key'=[guid]::NewGuid().ToString() }
    if ($script:token) { $headers.Authorization="Bearer $script:token" }
    $args=@{Uri="$base/$Path";Method=$Method;Headers=$headers;TimeoutSec=20}
    if($null -ne $Body){$args.ContentType='application/json';$args.Body=$Body|ConvertTo-Json -Depth 10}
    Invoke-RestMethod @args
}
$login = Call-Api 'auth/login' 'POST' @{username='e2e-farm-admin';password='synthetic-admin-runtime-only-2026'}
$script:token=$login.accessToken
$me=Call-Api 'me'
$building=[guid]::NewGuid().ToString(); $pen=[guid]::NewGuid().ToString(); $code='VIDEO-'+[guid]::NewGuid().ToString('N').Substring(0,8)
Call-Api "master-data/buildings/$building" 'PUT' @{parentId=$me.activeOrganizationId;code=$code;name='Synthetic video building';enabled=$true;expectedVersion=0;reason='Synthetic video acceptance'} | Out-Null
Call-Api "master-data/pens/$pen" 'PUT' @{parentId=$building;code='VIDEO';name='Synthetic video pen';enabled=$true;expectedVersion=0;reason='Synthetic video acceptance'} | Out-Null
$date=Get-Date -Format 'yyyy-MM-dd'
$package=Call-Api 'upload-packages' 'POST' @{clientPackageId=[guid]::NewGuid().ToString();organizationId=$me.activeOrganizationId;penId=$pen;businessDate=$date;captureKind='video'}
$asset=[guid]::NewGuid().ToString(); $bytes=[IO.File]::ReadAllBytes($fixture); $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
Invoke-WebRequest -Uri "$base/upload-packages/$($package.id)/blobs/$asset" -Method Put -Headers @{Authorization="Bearer $script:token";'X-Idempotency-Key'=[guid]::NewGuid().ToString();'X-Content-SHA256'=$hash} -ContentType 'application/octet-stream' -Body $bytes | Out-Null
$set=[guid]::NewGuid().ToString()
Call-Api "upload-packages/$($package.id)/manifest" 'PUT' @{captureSetId=$set;captureKind='video';penId=$pen;assets=@(@{assetId=$asset;viewPosition='video';capturedAt=[DateTimeOffset]::UtcNow.ToString('o');originalName='synthetic.mp4';width=160;height=120;sha256=$hash;byteSize=$bytes.Length;mediaType='video/mp4';exif=@{};roi=$null})} | Out-Null
$commit=Call-Api "upload-packages/$($package.id)/commit" 'POST'
# The dispatcher is deliberately disabled in this fixed browser stack. Submit this one job to real Celery.
$payload=@{job_id=$commit.inferenceJobId;correlation_id='synthetic-video-runtime';organization_id=$me.activeOrganizationId;capture_set_id=$set;capture_kind='video';media=@(@{asset_id=$asset;view_position='video';object_uri="s3://pig-inventory/synthetic/$asset.mp4";sha256=$hash;roi=$null});requested_model=@{model_key='pending-license-review';version='unverified';checksum='unverified';adapter_version='http-v1'}}
$payload|ConvertTo-Json -Depth 10|docker exec -i pig-inventory-p0-admin-runtime-inference-api-1 python -c 'import sys,json,httpx; r=httpx.post("http://localhost:8000/v1/jobs",json=json.load(sys.stdin)); r.raise_for_status(); print(r.status_code)'
if($LASTEXITCODE -ne 0){throw 'Real Celery submission failed.'}
$session=$null
for($attempt=0;$attempt -lt 20;$attempt++){
    $session=Call-Api "inventory-sessions/$($commit.sessionId)"
    if($session.PSObject.Properties['inferenceStatus'] -and $session.inferenceStatus -eq 'review_required'){break}
    Start-Sleep -Seconds 1
}
if($session.status -ne 'review_required' -or $session.inferenceStatus -ne 'review_required' -or ($session.PSObject.Properties['count'] -and $null -ne $session.count)){throw 'Video must remain manual without a candidate count.'}
$sql="SELECT inference_source FROM count_result WHERE inference_job_id=UUID_TO_BIN('$($commit.inferenceJobId)');"
$source=$sql|docker exec -i pig-inventory-p0-admin-runtime-mysql-1 sh -lc 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" -N -B'
if($LASTEXITCODE -ne 0 -or $source -ne 'manual-video-evidence'){throw 'Real worker result source does not match manual video mode.'}
$download=Join-Path $output 'video-readback.mp4'
Invoke-WebRequest -Uri "$base/media-assets/$asset/content" -Headers @{Authorization="Bearer $script:token"} -OutFile $download | Out-Null
if((Get-FileHash $download -Algorithm SHA256).Hash.ToLowerInvariant() -ne $hash){throw 'Video content changed in transit.'}
Call-Api "inventory-sessions/$($commit.sessionId)/confirm" 'POST' @{confirmedCount=0;reason='Synthetic empty scene manual confirmation'} | Out-Null
$media=@(Call-Api "inventory-sessions/$($commit.sessionId)/media")
if($media.Count -ne 1 -or -not $media[0].locked){throw 'Confirmed video evidence must be locked.'}
$delete=Invoke-WebRequest -Uri "$base/media-assets/$asset" -Method Delete -Headers @{Authorization="Bearer $script:token";'X-Idempotency-Key'=[guid]::NewGuid().ToString()} -SkipHttpErrorCheck
if([int]$delete.StatusCode -ne 409){throw 'Locked video deletion must be denied.'}
@{status='passed';project=$project;videoUploaded=$true;workerCallback='manual-video-evidence';candidateCount=$null;contentHashMatched=$true;confirmedMediaLocked=$true;ordinaryDeleteStatus=409;devicePlayback='pending'}|ConvertTo-Json|Set-Content (Join-Path $output 'video-summary.json')
Get-Content (Join-Path $output 'video-summary.json')
