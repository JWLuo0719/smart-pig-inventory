[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$config = Join-Path $repositoryRoot 'apps/mobile/android/key.properties'
$signingDirectory = Join-Path $env:LOCALAPPDATA 'PigInventory/signing'
$keystore = Join-Path $signingDirectory 'inventory-candidate.p12'
if ((Test-Path -LiteralPath $config) -or (Test-Path -LiteralPath $keystore)) {
    throw 'Signing material already exists. Refusing to overwrite or rotate it.'
}
New-Item -ItemType Directory -Path $signingDirectory -Force | Out-Null
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls.exe $signingDirectory /inheritance:r /grant:r "${identity}:(OI)(CI)F" 'SYSTEM:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Cannot restrict signing directory permissions.' }
$password = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
try {
    $env:PIG_SIGNING_INIT_PASSWORD = $password
    & keytool -genkeypair -keystore $keystore -storetype PKCS12 -alias inventory-release -keyalg RSA -keysize 3072 -validity 10000 -dname 'CN=Pig Inventory Candidate, OU=Local Candidate, O=Pig Inventory' -storepass:env PIG_SIGNING_INIT_PASSWORD -keypass:env PIG_SIGNING_INIT_PASSWORD
    if ($LASTEXITCODE -ne 0) { throw 'Keystore creation failed.' }
    # Create the file exclusively, restrict permissions before writing secrets.
    $stream = [IO.File]::Open($config, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $stream.Dispose()
    & icacls.exe $config /inheritance:r /grant:r "${identity}:F" 'SYSTEM:F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Cannot restrict key.properties permissions.' }
    $portablePath = $keystore.Replace('\', '/')
    "storeFile=$portablePath`nstorePassword=$password`nkeyAlias=inventory-release`nkeyPassword=$password`n" |
        Set-Content -LiteralPath $config -Encoding ascii
    $certificate = Join-Path $signingDirectory 'inventory-candidate.cer'
    & keytool -exportcert -keystore $keystore -alias inventory-release -storepass:env PIG_SIGNING_INIT_PASSWORD -file $certificate
    if ($LASTEXITCODE -ne 0) { throw 'Certificate export failed.' }
    $fingerprint = (Get-FileHash -LiteralPath $certificate -Algorithm SHA256).Hash.ToLowerInvariant()
    $fingerprint | Set-Content -LiteralPath (Join-Path $signingDirectory 'certificate-sha256.txt')
    Write-Output "[OK] Candidate signing identity created. Certificate SHA-256: $fingerprint"
    Write-Output '[INFO] Keep key.properties and the keystore together in a secure backup before distribution. No off-device backup has been made.'
} finally {
    Remove-Item Env:PIG_SIGNING_INIT_PASSWORD -ErrorAction SilentlyContinue
    $password = $null
}
