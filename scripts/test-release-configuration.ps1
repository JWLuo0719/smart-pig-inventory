[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$android = Join-Path $repositoryRoot 'apps/mobile/android'
$output = Join-Path $repositoryRoot ('artifacts/release-gates/' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $output | Out-Null
$names = @('ANDROID_RELEASE_STORE_FILE', 'ANDROID_RELEASE_STORE_PASSWORD', 'ANDROID_RELEASE_KEY_ALIAS', 'ANDROID_RELEASE_KEY_PASSWORD')
$saved = @{}
foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$results = [Collections.Generic.List[object]]::new()
function Invoke-Gate {
    param([string]$Name, [string[]]$Definitions, [string]$ExpectedError = '', [string]$Task = ':app:validateReleaseConfiguration')
    $encoded = @($Definitions | ForEach-Object { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($_)) }) -join ','
    $log = Join-Path $output "$Name.log"
    & ./gradlew.bat $Task "-Pdart-defines=$encoded" --console=plain *> $log
    $code = $LASTEXITCODE
    if ($ExpectedError) {
        if ($code -eq 0 -or -not (Select-String -LiteralPath $log -SimpleMatch $ExpectedError)) { throw "Gate failed: $Name. Inspect $log" }
    } elseif ($code -ne 0) { throw "Gate failed: $Name. Inspect $log" }
    $results.Add(@{name=$Name; passed=$true; exitCode=$code})
    Write-Output "[OK] $Name"
}
Push-Location $android
try {
    foreach ($name in $names) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
    $env:ANDROID_RELEASE_STORE_FILE = 'missing.p12'
    Invoke-Gate 'partial-env-no-fallback' @('API_BASE_URL=https://api.pig-inventory.invalid') 'Release signing is required'
    # The Debug pre-build must still work with incomplete Release inputs.
    Invoke-Gate 'debug-independent-of-release' @() '' ':app:preDebugBuild'
    $env:ANDROID_RELEASE_STORE_PASSWORD = 'android'
    $env:ANDROID_RELEASE_KEY_ALIAS = 'androiddebugkey'
    $env:ANDROID_RELEASE_KEY_PASSWORD = 'android'
    $env:ANDROID_RELEASE_STORE_FILE = Join-Path $env:USERPROFILE '.android/debug.keystore'
    Invoke-Gate 'debug-certificate-rejected' @('API_BASE_URL=https://api.pig-inventory.invalid') 'Android Debug certificates are forbidden'
    foreach ($name in $names) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
    Invoke-Gate 'missing-endpoint' @() 'exactly one explicit API_BASE_URL'
    Invoke-Gate 'http-rejected' @('API_BASE_URL=http://api.pig-inventory.invalid') 'stable HTTPS DNS URL'
    Invoke-Gate 'ip-rejected' @('API_BASE_URL=https://192.168.1.2') 'stable HTTPS DNS URL'
    Invoke-Gate 'credentials-rejected' @('API_BASE_URL=https://user:pass@api.pig-inventory.invalid') 'stable HTTPS DNS URL'
    Invoke-Gate 'duplicate-endpoint-rejected' @('API_BASE_URL=https://a.invalid', 'API_BASE_URL=https://b.invalid') 'exactly one explicit API_BASE_URL'
    Invoke-Gate 'valid-local-signing-https' @('API_BASE_URL=https://api.pig-inventory.invalid')
    Invoke-Gate 'lan-ca-required' @('API_BASE_URL=https://pig-inventory.local:8443') 'LAN acceptance requires exactly one explicit certificate'
    Invoke-Gate 'lan-ca-host-restricted' @('API_BASE_URL=https://api.pig-inventory.invalid','LAN_ACCEPTANCE_CA_BASE64=dGVzdA==') 'LAN certificate is restricted'
    $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'summary.json')
} finally {
    Pop-Location
    foreach ($name in $names) {
        if ($null -eq $saved[$name]) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    }
}
