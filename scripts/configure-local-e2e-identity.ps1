[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $repositoryRoot '.env'

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

function New-HexSecret {
    param([int]$Bytes = 24)
    return ([BitConverter]::ToString((New-RandomBytes -Bytes $Bytes))).Replace('-', '').ToLowerInvariant()
}

function New-Base64Secret {
    return [Convert]::ToBase64String((New-RandomBytes -Bytes 32))
}

try {
    if (-not (Test-Path -LiteralPath $envFile)) {
        throw "Missing $envFile. Run .\scripts\initialize-local-dev.ps1 for a new local environment."
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    Get-Content -LiteralPath $envFile | ForEach-Object { $lines.Add($_) }
    $generated = 0
    $required = [ordered]@{
        'SECURITY_ENABLED' = 'true'
        'JWT_SIGNING_SECRET' = (New-Base64Secret)
        'APP_BOOTSTRAP_ADMIN_USERNAME' = 'local-admin'
        'APP_BOOTSTRAP_ADMIN_PASSWORD' = (New-HexSecret -Bytes 24)
        'APP_BOOTSTRAP_ADMIN_DISPLAY_NAME' = 'Local E2E Administrator'
        'APP_BOOTSTRAP_ORGANIZATION_CODE' = 'DEV-E2E'
        'APP_BOOTSTRAP_ORGANIZATION_NAME' = 'Local E2E Synthetic Farm'
    }

    foreach ($name in $required.Keys) {
        $pattern = "^$([regex]::Escape($name))="
        $index = -1
        for ($position = 0; $position -lt $lines.Count; $position++) {
            if ($lines[$position] -match $pattern) {
                $index = $position
                break
            }
        }

        if ($name -eq 'SECURITY_ENABLED') {
            $replacement = "$name=true"
            if ($index -ge 0) {
                $lines[$index] = $replacement
            }
            else {
                $lines.Add($replacement)
            }
            continue
        }

        if ($index -ge 0) {
            $existing = $lines[$index] -replace $pattern, ''
            if (-not [string]::IsNullOrWhiteSpace($existing)) {
                continue
            }
            $lines[$index] = "$name=$($required[$name])"
        }
        else {
            $lines.Add("$name=$($required[$name])")
        }
        $generated++
    }

    [System.IO.File]::WriteAllLines($envFile, $lines, [System.Text.UTF8Encoding]::new($false))
    Write-Output "[OK] Local identity configuration is enabled. Generated $generated missing local-only value(s); no credentials or keys were displayed."
    Write-Output '[INFO] Restart the Compose stack so business-api reads the updated environment.'
}
catch {
    Write-Error $_
    exit 1
}
