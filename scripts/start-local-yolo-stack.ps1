[CmdletBinding()]
param(
    [string]$RunnerRoot = 'E:\pig-model-runner',
    [int]$RunnerPort = 9000,
    [int]$GatewayPort = 8088,
    [int]$MinioHostPort = 9100,
    [int]$MinioConsoleHostPort = 9101,
    [switch]$SkipRunnerSetup,
    [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProductRoot = Split-Path -Parent $PSScriptRoot
$RunnerRoot = [System.IO.Path]::GetFullPath($RunnerRoot)
$RunDirectory = Join-Path $RunnerRoot '.run'
$RunnerLog = Join-Path $RunDirectory 'runner.log'
$RunnerErrLog = Join-Path $RunDirectory 'runner.err.log'
$RunnerPidFile = Join-Path $RunDirectory 'runner.pid'

function Write-Step {
    param([string]$Message)
    Write-Host "[smart-pig] $Message"
}

function Assert-Command {
    param([string]$Name)
    if ($null -eq (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name was not found on PATH. Install it or open a new PowerShell window after installation."
    }
}

function Wait-HttpOk {
    param(
        [string]$Url,
        [int]$TimeoutSeconds = 120
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastError = $null
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
                return $response.Content
            }
        }
        catch {
            $lastError = $_.Exception.Message
        }
        Start-Sleep -Seconds 3
    }
    throw "Timed out waiting for $Url. Last error: $lastError"
}

function Test-RunnerReady {
    $url = "http://localhost:$RunnerPort/health/ready"
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 3
        return $response.StatusCode -eq 200
    }
    catch {
        return $false
    }
}

function Start-Runner {
    if (-not (Test-Path -LiteralPath $RunnerRoot)) {
        throw "Runner root not found: $RunnerRoot"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $RunnerRoot '.env'))) {
        $example = Join-Path $RunnerRoot '.env.example'
        if (-not (Test-Path -LiteralPath $example)) {
            throw "Runner .env is missing and .env.example was not found."
        }
        Copy-Item -LiteralPath $example -Destination (Join-Path $RunnerRoot '.env')
        Write-Step "Created runner .env from .env.example. Review it before full E2E testing."
    }
    if (-not (Test-Path -LiteralPath (Join-Path $RunnerRoot '.venv\Scripts\python.exe'))) {
        if ($SkipRunnerSetup) {
            throw "Runner .venv is missing. Run $RunnerRoot\scripts\setup-venv.ps1 first."
        }
        Write-Step "Runner .venv is missing; running setup-venv.ps1."
        & (Join-Path $RunnerRoot 'scripts\setup-venv.ps1')
    }
    if (Test-RunnerReady) {
        Write-Step "Runner is already ready on port $RunnerPort."
        return
    }

    New-Item -ItemType Directory -Force -Path $RunDirectory | Out-Null
    if (Test-Path -LiteralPath $RunnerLog) { Remove-Item -LiteralPath $RunnerLog -Force }
    if (Test-Path -LiteralPath $RunnerErrLog) { Remove-Item -LiteralPath $RunnerErrLog -Force }

    $python = Join-Path $RunnerRoot '.venv\Scripts\python.exe'
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-Command',
        "& { Set-Location '$RunnerRoot'; & '$python' -m uvicorn app.main:app --host 0.0.0.0 --port $RunnerPort --env-file .env }"
    )
    $process = Start-Process -FilePath 'powershell.exe' `
        -ArgumentList $arguments `
        -WorkingDirectory $RunnerRoot `
        -WindowStyle Hidden `
        -RedirectStandardOutput $RunnerLog `
        -RedirectStandardError $RunnerErrLog `
        -PassThru
    [System.IO.File]::WriteAllText($RunnerPidFile, [string]$process.Id)
    Write-Step "Started runner in background. PID=$($process.Id). Logs: $RunnerLog"
    Wait-HttpOk -Url "http://localhost:$RunnerPort/health/ready" -TimeoutSeconds 180 | Out-Null
    Write-Step "Runner is ready: http://localhost:$RunnerPort/health/ready"
}

function Start-ProductStack {
    Assert-Command docker
    docker info *> $null

    $envFile = Join-Path $ProductRoot '.env'
    if (-not (Test-Path -LiteralPath $envFile)) {
        Write-Step "Product .env is missing; running initialize-local-dev.ps1."
        & (Join-Path $ProductRoot 'scripts\initialize-local-dev.ps1')
    }

    $env:GATEWAY_PORT = [string]$GatewayPort
    $env:MINIO_HOST_PORT = [string]$MinioHostPort
    $env:MINIO_CONSOLE_HOST_PORT = [string]$MinioConsoleHostPort

    $composeArgs = @(
        'compose',
        '-f', 'docker-compose.yml',
        '-f', 'docker-compose.runner-local.yml',
        'up'
    )
    if (-not $SkipBuild) {
        $composeArgs += '--build'
    }
    $composeArgs += '-d'

    Write-Step "Starting product stack with Docker Compose."
    Push-Location $ProductRoot
    try {
        & docker @composeArgs
    }
    finally {
        Pop-Location
    }

    Wait-HttpOk -Url "http://localhost:$GatewayPort/actuator/health" -TimeoutSeconds 240 | Out-Null
    Write-Step "Gateway is healthy: http://localhost:$GatewayPort"

    Wait-HttpOk -Url "http://localhost:$MinioHostPort/minio/health/live" -TimeoutSeconds 120 | Out-Null
    Write-Step "MinIO is reachable from host: http://localhost:$MinioHostPort"
}

function Test-ContainerCanReachRunner {
    Push-Location $ProductRoot
    try {
        $probe = "import urllib.request; print(urllib.request.urlopen('http://host.docker.internal:$RunnerPort/health/ready', timeout=10).read().decode())"
        & docker compose -f docker-compose.yml -f docker-compose.runner-local.yml exec -T inference-api python -c $probe | Out-Null
        Write-Step "inference-api can reach runner through host.docker.internal:$RunnerPort."
    }
    catch {
        Write-Warning "Could not verify container -> runner connectivity yet: $($_.Exception.Message)"
    }
    finally {
        Pop-Location
    }
}

Write-Step "Product root: $ProductRoot"
Write-Step "Runner root: $RunnerRoot"
Start-Runner
Start-ProductStack
Test-ContainerCanReachRunner

Write-Host ''
Write-Host 'All local services are started.'
Write-Host "Runner:  http://localhost:$RunnerPort/health/ready"
Write-Host "Web/API: http://localhost:$GatewayPort"
Write-Host "MinIO:   http://localhost:$MinioHostPort"
Write-Host ''
Write-Host 'Build Android APK example:'
Write-Host "  .\scripts\build-lan-test-apk.ps1 -ApiBaseUrl http://<your-LAN-IP>:$GatewayPort"
Write-Host ''
Write-Host 'Runner logs:'
Write-Host "  Get-Content -Wait '$RunnerLog'"
