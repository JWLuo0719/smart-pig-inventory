[CmdletBinding()]
param(
    [ValidatePattern('^https?://')]
    [string]$ApiBaseUrl,
    [switch]$SkipApiHealthCheck,
    [switch]$Install
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$mobileDirectory = Join-Path $repositoryRoot 'apps\mobile'
$apkPath = Join-Path $mobileDirectory 'build\app\outputs\flutter-apk\app-debug.apk'

function Test-PrivateIpv4 {
    param([string]$Address)

    return $Address -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)'
}

function Get-DefaultLanAddress {
    $physicalInterfaceIndexes = @(Get-NetAdapter |
        Where-Object { $_.Status -eq 'Up' -and $_.HardwareInterface } |
        Select-Object -ExpandProperty ifIndex)
    $privateAddresses = @(Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object {
            (Test-PrivateIpv4 -Address $_.IPAddress) -and
            $_.PrefixOrigin -ne 'WellKnown'
        })
    $physicalAddresses = @($privateAddresses | Where-Object {
        $physicalInterfaceIndexes -contains $_.InterfaceIndex
    })
    $address = $physicalAddresses | Select-Object -First 1
    if ($null -eq $address) {
        throw 'No private IPv4 address was found on an active physical network adapter. Connect to the test LAN or pass -ApiBaseUrl explicitly.'
    }
    return $address.IPAddress
}

function Assert-ApiHealthy {
    param([string]$BaseUrl)

    $healthUrl = "$($BaseUrl.TrimEnd('/'))/actuator/health"
    try {
        $response = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 10
    }
    catch {
        throw "The LAN API is not reachable at $healthUrl. Start Docker Compose, check the Windows private-network firewall rule, or use -SkipApiHealthCheck only to build without a running server."
    }
    if ($response.StatusCode -ne 200) {
        throw "The LAN API health check returned HTTP $($response.StatusCode) at $healthUrl."
    }
    Write-Output "[OK] API health check passed: $healthUrl"
}

try {
    if ([string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
        $lanAddress = Get-DefaultLanAddress
        $ApiBaseUrl = "http://${lanAddress}:8088"
    }

    $uri = [Uri]$ApiBaseUrl
    if (-not $uri.IsAbsoluteUri -or ($uri.Scheme -ne 'http' -and $uri.Scheme -ne 'https') -or -not [string]::IsNullOrEmpty($uri.UserInfo)) {
        throw 'ApiBaseUrl must be an absolute HTTP(S) URL without embedded credentials.'
    }
    $ApiBaseUrl = $ApiBaseUrl.TrimEnd('/')

    if (-not $SkipApiHealthCheck) {
        Assert-ApiHealthy -BaseUrl $ApiBaseUrl
    }
    else {
        Write-Output '[WARN] API health check skipped. This APK must not be reported as LAN E2E tested.'
    }

    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    $flutterPath = if ($null -ne $flutterCommand) {
        $flutterCommand.Source
    }
    else {
        'D:\ProgrammingLanguage\Flutter\flutter\bin\flutter.bat'
    }
    if (-not (Test-Path -LiteralPath $flutterPath)) {
        throw 'Flutter was not found on PATH or at D:\ProgrammingLanguage\Flutter\flutter\bin\flutter.bat.'
    }
    Push-Location $mobileDirectory
    try {
        & $flutterPath build apk --debug "--dart-define=API_BASE_URL=$ApiBaseUrl"
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter build failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }

    if (-not (Test-Path -LiteralPath $apkPath)) {
        throw "Flutter reported success but the APK was not found: $apkPath"
    }
    $hash = (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Output "[OK] LAN test APK: $apkPath"
    Write-Output "[OK] API base URL embedded in this debug APK: $ApiBaseUrl"
    Write-Output "[OK] APK SHA-256: $hash"
    Write-Output '[INFO] Debug APKs permit cleartext HTTP only for private-LAN development. Release APKs must use HTTPS.'

    if ($Install) {
        $adb = Get-Command adb -ErrorAction Stop
        & $adb.Source install -r $apkPath
        if ($LASTEXITCODE -ne 0) {
            throw "ADB installation failed with exit code $LASTEXITCODE."
        }
        Write-Output '[OK] APK installed through ADB.'
    }
}
catch {
    Write-Error $_
    exit 1
}
