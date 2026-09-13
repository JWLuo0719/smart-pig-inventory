[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ApiBaseUrl,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedCertificateSha256,
    [switch]$BuildOnly,
    [string]$LanCaCertificate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$mobileDirectory = Join-Path $repositoryRoot 'apps/mobile'

try {
    $uri = [Uri]$ApiBaseUrl
    if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne 'https' -or
        $uri.HostNameType -ne [UriHostNameType]::Dns -or $uri.IsLoopback -or
        $uri.Host.EndsWith('.localhost') -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) {
        throw 'Release requires a stable HTTPS DNS URL without credentials, query, fragment or IP literals.'
    }
    $ApiBaseUrl = $ApiBaseUrl.TrimEnd('/')
    $extraDefines = @()
    if ($LanCaCertificate) {
        if ($uri.Host -ne 'pig-inventory.local') { throw 'LAN CA is restricted to pig-inventory.local.' }
        $caBytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $LanCaCertificate).Path)
        $extraDefines += '--dart-define=LAN_ACCEPTANCE_CA_BASE64=' + [Convert]::ToBase64String($caBytes)
    } elseif ($uri.Host -eq 'pig-inventory.local') { throw 'The LAN acceptance host requires -LanCaCertificate.' }
    if (-not $BuildOnly) {
        if ($uri.Host.EndsWith('.invalid') -or $uri.Host.EndsWith('.test') -or $uri.Host.EndsWith('.example')) {
            throw 'Reserved test domains require -BuildOnly and cannot be delivered for acceptance.'
        }
        if ($LanCaCertificate) {
            # Private CA has no online CRL; still verify chain, validity and hostname.
            $healthJson = & curl.exe --silent --show-error --fail --ssl-revoke-best-effort --noproxy '*' --cacert $LanCaCertificate --max-time 15 "$ApiBaseUrl/actuator/health"
            if ($LASTEXITCODE -ne 0) { throw 'LAN HTTPS certificate/health verification failed.' }
            $health = $healthJson | ConvertFrom-Json
        } else {
            $health = Invoke-RestMethod -Uri "$ApiBaseUrl/actuator/health" -TimeoutSec 15
        }
        if ($health.status -ne 'UP') { throw 'API health is not UP.' }
    }
    $sdk = $env:ANDROID_SDK_ROOT
    if (-not $sdk) { $sdk = $env:ANDROID_HOME }
    if (-not $sdk) { throw 'Set ANDROID_SDK_ROOT to the installed Android SDK.' }
    $buildTools = Get-ChildItem -LiteralPath (Join-Path $sdk 'build-tools') -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
        Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    if ($null -eq $buildTools) { throw 'Android SDK build-tools were not found.' }
    $apksigner = Join-Path $buildTools.FullName 'apksigner.bat'
    $aapt = Join-Path $buildTools.FullName 'aapt.exe'
    $flutter = (Get-Command flutter -ErrorAction Stop).Source
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $outputDirectory = Join-Path $repositoryRoot "artifacts/android-release/$stamp"
    New-Item -ItemType Directory -Path $outputDirectory -ErrorAction Stop | Out-Null
    $started = [DateTime]::UtcNow
    Push-Location $mobileDirectory
    try {
        & $flutter build apk --release "--dart-define=API_BASE_URL=$ApiBaseUrl" @extraDefines
        if ($LASTEXITCODE -ne 0) { throw 'Flutter Release build failed; no verified artifact was created.' }
    } finally { Pop-Location }
    $sourceApk = Join-Path $mobileDirectory 'build/app/outputs/flutter-apk/app-release.apk'
    if (-not (Test-Path -LiteralPath $sourceApk) -or (Get-Item -LiteralPath $sourceApk).LastWriteTimeUtc -lt $started) {
        throw 'A fresh Release APK was not produced.'
    }
    $signature = @(& $apksigner verify --verbose --print-certs $sourceApk 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed.' }
    $certificateMatches = [regex]::Matches(($signature -join "`n"), '(?m)^Signer #\d+ certificate SHA-256 digest: ([a-fA-F0-9]{64})\s*$')
    if ($certificateMatches.Count -ne 1 -or $certificateMatches[0].Groups[1].Value -ne $ExpectedCertificateSha256) {
        throw 'APK certificate does not match the independently selected release certificate.'
    }
    if (($signature -join "`n") -match 'CN=Android Debug') { throw 'Debug certificate rejected.' }
    $badging = @(& $aapt dump badging $sourceApk 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect APK package metadata.' }
    $package = [regex]::Match(($badging -join "`n"), "package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'")
    $version = [regex]::Match((Get-Content (Join-Path $mobileDirectory 'pubspec.yaml') -Raw), '(?m)^version:\s*([^+\s]+)\+(\d+)\s*$')
    if (-not $package.Success -or -not $version.Success -or
        $package.Groups[1].Value -ne 'com.smartfarm.smart_pig_inventory' -or
        $package.Groups[2].Value -ne $version.Groups[2].Value -or
        $package.Groups[3].Value -ne $version.Groups[1].Value -or
        ($badging -join "`n") -match 'application-debuggable') { throw 'Release package/version/debuggable verification failed.' }
    $manifest = @(& $aapt dump xmltree $sourceApk AndroidManifest.xml 2>&1)
    if ($LASTEXITCODE -ne 0 -or ($manifest -join "`n") -notmatch 'usesCleartextTraffic[^\r\n]*=\(type 0x12\)0x0') {
        throw 'Release manifest must explicitly disable cleartext traffic.'
    }
    $filename = if ($BuildOnly) { 'inventory-release-build-only.apk' } elseif ($LanCaCertificate) { 'inventory-release-lan-acceptance.apk' } else { 'inventory-release-candidate.apk' }
    $apk = Join-Path $outputDirectory $filename
    Copy-Item -LiteralPath $sourceApk -Destination $apk
    $hash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
    $signature | Set-Content -LiteralPath (Join-Path $outputDirectory 'signature.txt')
    [ordered]@{
        status = 'signed-build-verified'; buildOnly = [bool]$BuildOnly
        lanAcceptance = [bool]$LanCaCertificate
        lanCaFileSha256 = $(if ($LanCaCertificate) { (Get-FileHash -LiteralPath $LanCaCertificate -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null })
        apiHealthChecked = -not [bool]$BuildOnly; apiBaseUrl = $ApiBaseUrl
        apk = $filename; sha256 = $hash; certificateSha256 = $ExpectedCertificateSha256.ToLowerInvariant()
        versionName = $package.Groups[3].Value; versionCode = $package.Groups[2].Value
        cleartextTraffic = $false; debuggable = $false
        runtimeAcceptance = 'pending'; modelApproved = $false
        createdAt = [DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $outputDirectory 'build-evidence.json')
    Write-Output "[OK] Signed APK: $apk"
    Write-Output "[OK] SHA-256: $hash"
    if ($BuildOnly) { Write-Output '[WARN] Build-only artifact: endpoint/runtime/AI acceptance NOT verified. Do not install over existing drafts.' }
} catch {
    Write-Error $_
    exit 1
}
