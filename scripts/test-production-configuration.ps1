#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$EnvironmentFile)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$resolved = (Resolve-Path -LiteralPath $EnvironmentFile).Path
$json = & docker compose -p pig-inventory-production --env-file $resolved -f "$root/docker-compose.yml" -f "$root/docker-compose.production.yml" config --format json
if ($LASTEXITCODE -ne 0) { throw 'Production Compose cannot be resolved. No deployment performed.' }
$config = ($json -join "`n") | ConvertFrom-Json -AsHashtable
$api = $config.services.'business-api'.environment
foreach ($pair in @(@('mysql','MYSQL_ROOT_PASSWORD'),@('minio','MINIO_ROOT_PASSWORD'))) {
    $secret = [string]$config.services[$pair[0]].environment[$pair[1]]
    if ($secret.Length -lt 32 -or $secret -match '(?i)change.me|synthetic|example') { throw "Production storage secret is missing or unsuitable: $($pair[1])" }
}
foreach ($key in @('MYSQL_PASSWORD','JWT_SIGNING_SECRET','INFERENCE_CALLBACK_TOKEN','MONITORING_SERVICE_KEY')) {
    if (-not $api.ContainsKey($key) -or ([string]$api[$key]).Length -lt 32 -or ([string]$api[$key]) -match '(?i)change.me|synthetic|example') { throw "Production secret is missing or unsuitable: $key" }
}
if ($api.JWT_SIGNING_SECRET -eq $api.INFERENCE_CALLBACK_TOKEN -or $api.MONITORING_SERVICE_KEY -eq $api.INFERENCE_CALLBACK_TOKEN -or $api.MONITORING_SERVICE_KEY -eq $api.JWT_SIGNING_SECRET) { throw 'JWT, callback and monitoring keys must be independent.' }
if ($api.SECURITY_ENABLED -ne 'true' -or $api.APP_E2E_FIXTURES_ENABLED -ne 'false' -or $api.SPRING_PROFILES_ACTIVE -ne 'prod' -or $api.INFERENCE_DISPATCHER_ENABLED -ne 'true') { throw 'Production authentication/fixture/dispatcher settings are invalid.' }
if ([string]::IsNullOrWhiteSpace($api.APP_BOOTSTRAP_ADMIN_USERNAME) -or ([string]$api.APP_BOOTSTRAP_ADMIN_PASSWORD).Length -lt 16 -or [string]::IsNullOrWhiteSpace($api.APP_BOOTSTRAP_ORGANIZATION_CODE) -or [string]::IsNullOrWhiteSpace($api.APP_BOOTSTRAP_ORGANIZATION_NAME)) { throw 'Initial production administrator and farm must be configured.' }
$uri = [Uri]$api.CORS_ALLOWED_ORIGINS
if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne 'https' -or $uri.IsLoopback -or $uri.Host -match '\.(invalid|test|example|local)$' -or $uri.HostNameType -ne 'Dns' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $uri.AbsolutePath -ne '/') { throw 'A real production HTTPS origin is required.' }
foreach ($service in @('business-api','admin-web','inference-api','inference-worker')) {
    $definition = $config.services[$service]
    if ($definition.ContainsKey('build') -or $definition.image -notmatch '@sha256:[a-f0-9]{64}$') { throw "Pin the verified image digest for $service; do not build on production." }
}
foreach ($service in @('inference-api','inference-worker')) {
    $settings = $config.services[$service].environment
    if ($settings.COUNTING_PROVIDER -ne 'unavailable' -or $settings.MODEL_APPROVED -ne 'false' -or $settings.MODEL_RESEARCH_ENABLED -ne 'false') { throw 'This candidate uses manual review until a separate model release is approved.' }
}
foreach ($entry in $config.services.GetEnumerator()) {
    if ($entry.Value.ContainsKey('ports')) {
        foreach ($port in $entry.Value.ports) { if ($entry.Key -ne 'gateway' -or $port.host_ip -ne '127.0.0.1') { throw 'Production internal services must not publish public ports.' } }
    }
}
[pscustomobject]@{ status = 'configuration-passed'; productionPublished = $false; imageDigestsPinned = $true; authenticationEnabled = $true; syntheticFixtures = $false; countingMode = 'manual-review'; remaining = 'Target TLS, backups/restoration, runtime and farm acceptance are still required.' } | ConvertTo-Json
