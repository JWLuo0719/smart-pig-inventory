[CmdletBinding()]
param(
    [string]$FlutterBin = 'D:\ProgrammingLanguage\Flutter\flutter\bin\flutter.bat'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$required = @(
    @{ Name = 'git'; Command = 'git'; Arguments = @('--version') },
    @{ Name = 'java'; Command = 'java'; Arguments = @('-version') },
    @{ Name = 'node'; Command = 'node'; Arguments = @('--version') },
    @{ Name = 'pnpm'; Command = 'pnpm'; Arguments = @('--version') },
    @{ Name = 'python'; Command = 'python'; Arguments = @('--version') },
    @{ Name = 'docker'; Command = 'docker'; Arguments = @('--version') }
)

$failed = New-Object System.Collections.Generic.List[string]
foreach ($tool in $required) {
    $command = Get-Command $tool.Command -ErrorAction SilentlyContinue
    if (-not $command) {
        Write-Host "[MISSING] $($tool.Name)" -ForegroundColor Yellow
        $failed.Add($tool.Name)
        continue
    }
    Write-Host "[OK] $($tool.Name): $($command.Source)" -ForegroundColor Green
}

if (-not (Test-Path -LiteralPath $FlutterBin)) {
    Write-Host "[MISSING] flutter: $FlutterBin" -ForegroundColor Yellow
    $failed.Add('flutter')
} else {
    Write-Host "[OK] flutter: $FlutterBin" -ForegroundColor Green
    & $FlutterBin --version
    & $FlutterBin doctor
    if ($LASTEXITCODE -ne 0) { $failed.Add('flutter doctor') }
}

$envFile = Join-Path $repositoryRoot '.env'
if (-not (Test-Path -LiteralPath $envFile)) {
    Write-Host '[MISSING] .env (run scripts/initialize-local-dev.ps1)' -ForegroundColor Yellow
    $failed.Add('.env')
} else {
    $unsafeDefault = Select-String -LiteralPath $envFile -Pattern '=change-(me|root-me|minio-me)$' -Quiet
    if ($unsafeDefault) {
        Write-Host '[FAIL] .env still contains template passwords.' -ForegroundColor Red
        $failed.Add('.env secrets')
    } else {
        Write-Host '[OK] .env exists and does not use template passwords.' -ForegroundColor Green
    }
}

if ($failed.Count -gt 0) {
    Write-Host "Environment is not ready: $($failed -join ', ')" -ForegroundColor Red
    exit 1
}

Write-Host 'Development environment readiness check passed.' -ForegroundColor Green
