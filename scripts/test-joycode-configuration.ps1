#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$EnvironmentFile)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$settings = @{}
foreach ($line in Get-Content -LiteralPath $EnvironmentFile) {
    if ($line -match '^([A-Z][A-Z0-9_]*)=(.*)$') { $settings[$Matches[1]] = $Matches[2].Trim() }
}
foreach ($key in @('MYSQL_URL','MYSQL_USER','MYSQL_PASSWORD','REDIS_HOST','MINIO_ENDPOINT','MINIO_ACCESS_KEY','MINIO_SECRET_KEY','MINIO_BUCKET','JWT_SIGNING_SECRET','CORS_ALLOWED_ORIGINS','INFERENCE_BASE_URL','INFERENCE_CALLBACK_TOKEN','MONITORING_SERVICE_KEY')) {
    if (-not $settings.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($settings[$key])) { throw "Missing cloud setting: $key" }
}
if ($settings.SECURITY_ENABLED -ne 'true' -or $settings.SPRING_PROFILES_ACTIVE -ne 'prod' -or $settings.APP_E2E_FIXTURES_ENABLED -ne 'false') { throw 'Cloud authentication/profile/fixture boundary is invalid' }
foreach ($key in @('MYSQL_PASSWORD','MINIO_SECRET_KEY','INFERENCE_CALLBACK_TOKEN','MONITORING_SERVICE_KEY')) {
    if ($settings[$key].Length -lt 32 -or $settings[$key] -match '(?i)synthetic|change.me|example') { throw "Unsuitable cloud secret: $key" }
}
try { $jwtBytes = [Convert]::FromBase64String($settings.JWT_SIGNING_SECRET) } catch { throw 'JWT signing setting must be Base64' }
if ($jwtBytes.Length -lt 32) { throw 'JWT signing setting is too short' }
if (@($settings.JWT_SIGNING_SECRET,$settings.INFERENCE_CALLBACK_TOKEN,$settings.MONITORING_SERVICE_KEY | Select-Object -Unique).Count -ne 3) { throw 'Signing/callback/monitoring secrets must be independent' }
if ($settings.CORS_ALLOWED_ORIGINS -notmatch '^https://[a-zA-Z0-9.-]+(:[0-9]+)?/?$' -or $settings.CORS_ALLOWED_ORIGINS -match '\.(invalid|example|local)(:|/|$)') { throw 'A verified public HTTPS origin is required' }
foreach ($key in @('MYSQL_URL','MINIO_ENDPOINT','INFERENCE_BASE_URL')) {
    if ($settings[$key] -match 'localhost|127\.0\.0\.1|pig-inventory\.local|\.invalid') { throw "Cloud data service must be independently configured: $key" }
}
foreach ($key in @('MODEL_APPROVED','MULTIVIEW_AUTO_COUNT_ENABLED','VIDEO_AUTO_COUNT_ENABLED')) {
    if (-not $settings.ContainsKey($key) -or $settings[$key] -ne 'false') { throw "Unapproved model flag: $key" }
}
if ($settings.ASSISTANT_ENABLED -eq 'true') {
    foreach ($key in @('ASSISTANT_MODEL_ENDPOINT','ASSISTANT_MODEL_NAME','ASSISTANT_MODEL_API_KEY')) {
        if (-not $settings.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($settings[$key])) { throw "Missing assistant setting: $key" }
    }
    $endpoint = [Uri]$settings.ASSISTANT_MODEL_ENDPOINT
    if ($settings.ASSISTANT_DATA_EGRESS_APPROVED -ne 'true' -or $endpoint.Scheme -ne 'https' -or $endpoint.UserInfo -or $endpoint.Query -or $endpoint.Fragment) { throw 'Assistant egress and HTTPS endpoint require explicit valid configuration' }
}
if ($settings.COMPETITION_VIEWER_PROVISION_ENABLED -eq 'true') {
    foreach ($key in @('COMPETITION_VIEWER_USERNAME','COMPETITION_VIEWER_PASSWORD','COMPETITION_VIEWER_ORGANIZATION_CODE','COMPETITION_VIEWER_EXPIRES_AT')) {
        if (-not $settings.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($settings[$key])) { throw "Missing competition viewer setting: $key" }
    }
    if ($settings.COMPETITION_VIEWER_PASSWORD.Length -lt 16) { throw 'Viewer credential is too short' }
    $expires = [DateTimeOffset]::Parse($settings.COMPETITION_VIEWER_EXPIRES_AT)
    if ($expires -le [DateTimeOffset]::UtcNow -or $expires -gt [DateTimeOffset]::UtcNow.AddDays(180)) { throw 'Viewer expiry is invalid' }
}
[pscustomobject]@{ status='configuration-passed'; containerBuilt=$false; deployed=$false; requires='Verify cloud middleware, TLS, model API, V14 migration and external judge access before acceptance' } | ConvertTo-Json
