[CmdletBinding()]
param(
    [string]$RunnerRoot = 'E:\pig-model-runner'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProductRoot = Split-Path -Parent $PSScriptRoot
$RunnerRoot = [System.IO.Path]::GetFullPath($RunnerRoot)
$RunnerPidFile = Join-Path $RunnerRoot '.run\runner.pid'

Write-Host '[smart-pig] Stopping Docker Compose stack.'
Push-Location $ProductRoot
try {
    docker compose -f docker-compose.yml -f docker-compose.runner-local.yml down
}
finally {
    Pop-Location
}

if (Test-Path -LiteralPath $RunnerPidFile) {
    $pidText = Get-Content -LiteralPath $RunnerPidFile -Raw
    $runnerPid = [int]$pidText.Trim()
    $process = Get-Process -Id $runnerPid -ErrorAction SilentlyContinue
    if ($null -ne $process) {
        Write-Host "[smart-pig] Stopping runner process PID=$runnerPid."
        Stop-Process -Id $runnerPid -Force
    }
    Remove-Item -LiteralPath $RunnerPidFile -Force
}
else {
    Write-Host '[smart-pig] No runner pid file found.'
}

Write-Host '[smart-pig] Local stack stopped.'

