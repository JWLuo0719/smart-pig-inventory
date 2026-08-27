[CmdletBinding()]
param(
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $repositoryRoot '.env'

if ((Test-Path -LiteralPath $envFile) -and -not $Force) {
    throw ".env already exists. Refusing to overwrite it; use -Force only after reviewing the existing file."
}

function New-RandomBytes {
    param([int]$Bytes)
    $buffer = [byte[]]::new($Bytes)
    $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($buffer)
    }
    finally {
        $generator.Dispose()
    }
    return ,$buffer
}

function New-Secret {
    param([int]$Bytes = 24)
    return ([BitConverter]::ToString((New-RandomBytes -Bytes $Bytes))).Replace('-', '').ToLowerInvariant()
}

function New-Base64Secret {
    param([int]$Bytes = 32)
    return [Convert]::ToBase64String((New-RandomBytes -Bytes $Bytes))
}

$content = @(
    'MYSQL_DATABASE=pig_inventory',
    'MYSQL_USER=pig_inventory',
    "MYSQL_PASSWORD=$(New-Secret)",
    "MYSQL_ROOT_PASSWORD=$(New-Secret)",
    'MINIO_ROOT_USER=pig_inventory_minio',
    "MINIO_ROOT_PASSWORD=$(New-Secret)",
    'MINIO_BUCKET=pig-inventory',
    '',
    '# Local-only identity bootstrap. Values are random/generated here and must never be committed or shared.',
    'SECURITY_ENABLED=true',
    "JWT_SIGNING_SECRET=$(New-Base64Secret)",
    'APP_BOOTSTRAP_ADMIN_USERNAME=local-admin',
    "APP_BOOTSTRAP_ADMIN_PASSWORD=$(New-Secret -Bytes 24)",
    'APP_BOOTSTRAP_ADMIN_DISPLAY_NAME=Local E2E Administrator',
    'APP_BOOTSTRAP_ORGANIZATION_CODE=DEV-E2E',
    'APP_BOOTSTRAP_ORGANIZATION_NAME=Local E2E Synthetic Farm',
    '',
    '# Only for local development. Shared and production environments must use a real issuer.',
    'OIDC_ISSUER_URI=https://identity.example.invalid/realms/pig-inventory',
    'COUNTING_PROVIDER=unavailable',
    'MODEL_KEY=',
    'MODEL_VERSION=',
    'MODEL_CHECKSUM='
)

[System.IO.File]::WriteAllLines($envFile, $content, [System.Text.UTF8Encoding]::new($false))
Write-Output "Created local-only configuration: $envFile"
Write-Output 'Secrets were generated locally and intentionally not printed.'
