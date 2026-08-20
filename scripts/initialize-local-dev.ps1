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

function New-Secret {
    param([int]$Bytes = 24)
    $buffer = [byte[]]::new($Bytes)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($buffer)
    return [Convert]::ToHexString($buffer).ToLowerInvariant()
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
