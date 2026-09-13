[CmdletBinding()]
param([string]$RunnerDirectory, [string]$BusinessImage)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$stateDirectory = Join-Path $repositoryRoot 'artifacts/lan-acceptance'
New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
$configPath = Join-Path $stateDirectory 'runtime.json'
if (Test-Path -LiteralPath $configPath) {
    $previous = Get-Content $configPath -Raw | ConvertFrom-Json
    if (-not $RunnerDirectory) { $RunnerDirectory = $previous.runnerDirectory }
    if (-not $BusinessImage) { $BusinessImage = $previous.businessImage }
}
if (-not $RunnerDirectory -or -not (Test-Path (Join-Path $RunnerDirectory 'scripts/start-runner.ps1'))) { throw 'Provide the existing external -RunnerDirectory.' }
if (-not $BusinessImage) { throw 'Provide the verified current-source -BusinessImage.' }
& (Join-Path $PSScriptRoot 'initialize-lan-tls.ps1')
$tls = Join-Path $stateDirectory 'tls'
New-Item -ItemType Directory -Path $tls -Force | Out-Null
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls.exe $tls /inheritance:r /grant:r "${identity}:(OI)(CI)F" 'SYSTEM:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Cannot restrict Docker TLS directory ACL.' }
foreach ($name in @('ca.pem','server.pem','server-key.pem')) {
    Copy-Item -LiteralPath (Join-Path (Join-Path $env:LOCALAPPDATA 'PigInventory/lan-tls') $name) -Destination $tls
}
& npm.cmd ci --ignore-scripts --prefix (Join-Path $repositoryRoot 'test-support/lan-acceptance')
if ($LASTEXITCODE -ne 0) { throw 'mDNS dependency installation failed.' }
@{runnerDirectory=$RunnerDirectory;businessImage=$BusinessImage;nodePath=(Get-Command node).Source} | ConvertTo-Json | Set-Content $configPath
# Replace only our supervisor and its mDNS child. The model and P0 data stay alive.
foreach ($entry in @(@{file='supervisor.pid';match='*start-lan-acceptance.ps1*'},@{file='mdns.pid';match='*lan-acceptance*mdns.cjs*'})) {
    $pidFile = Join-Path $stateDirectory $entry.file
    if (Test-Path $pidFile) {
        $managedId = [int](Get-Content $pidFile)
        $process = Get-CimInstance Win32_Process -Filter "ProcessId=$managedId" -ErrorAction SilentlyContinue
        if ($null -ne $process -and $process.CommandLine -like $entry.match) { Stop-Process -Id $managedId -ErrorAction Stop }
    }
}
$pwshPath = (Get-Command pwsh).Source
$script = Join-Path $PSScriptRoot 'start-lan-acceptance.ps1'
$arguments = '-NoProfile -WindowStyle Hidden -File "' + $script + '"'
$launch = '"' + $pwshPath + '" ' + $arguments
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'PigInventoryLanAcceptance' -Value $launch -PropertyType String -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$process = Start-Process $pwshPath -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $stateDirectory "supervisor-$stamp.stdout.log") -RedirectStandardError (Join-Path $stateDirectory "supervisor-$stamp.stderr.log")
$process.Id | Set-Content (Join-Path $stateDirectory 'supervisor.pid')
Write-Output '[OK] Current-user login startup registered. Inspect artifacts/lan-acceptance/status.json for readiness.'
Write-Output '[INFO] Firewall and real-device reachability are separate checks.'
