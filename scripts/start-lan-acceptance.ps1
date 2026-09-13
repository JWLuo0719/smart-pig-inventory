[CmdletBinding()]
param([switch]$Once)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$stateDirectory = Join-Path $repositoryRoot 'artifacts/lan-acceptance'
$config = Get-Content (Join-Path $stateDirectory 'runtime.json') -Raw | ConvertFrom-Json
$mutex = [Threading.Mutex]::new($false, 'Local\PigInventoryLanAcceptance')
if (-not $mutex.WaitOne(0)) { Write-Output 'LAN supervisor is already running.'; return }
$mdnsProcess = $null
$lastAddress = ''
$lastStatus = ''
$composeStarted = $false
Push-Location $repositoryRoot
try {
    do {
        try {
            $env:GATEWAY_PORT = '8089'
            $env:LAN_TLS_DIRECTORY = Join-Path $stateDirectory 'tls'
            $env:LAN_BUSINESS_IMAGE = $config.businessImage
            & docker info --format '{{.ServerVersion}}' *> $null
            if ($LASTEXITCODE -ne 0) {
                & docker desktop start *> (Join-Path $stateDirectory 'docker-start.log')
                throw 'Docker engine is not ready yet. Waiting for desktop startup.'
            }
            $environment = @{}
            Get-Content '.env' | ForEach-Object {
                if ($_ -match '^([^#=]+)=(.*)$') { $environment[$matches[1].Trim()] = $matches[2].Trim() }
            }
            if ($environment['COUNTING_PROVIDER'] -ne 'research-http-yolo' -or
                $environment['MODEL_APPROVED'] -ne 'false' -or
                $environment['MODEL_RESEARCH_ENABLED'] -ne 'true' -or
                $environment['SECURITY_ENABLED'] -ne 'true') { throw 'Expected secured research-only product settings.' }
            $runnerReady = $false
            try {
                $ready = Invoke-RestMethod 'http://127.0.0.1:9000/health/ready' -TimeoutSec 3
                $runnerReady = $ready.ready -and $ready.model_checksum -eq $environment['MODEL_CHECKSUM'] -and
                    $ready.model_key -eq $environment['MODEL_KEY'] -and $ready.model_version -eq $environment['MODEL_VERSION'] -and
                    $ready.adapter_version -eq $environment['MODEL_ADAPTER_VERSION'] -and $ready.research_force_review -and
                    $ready.confidence_threshold -eq 0.6 -and $ready.iou_threshold -eq 0.7 -and $ready.image_size -eq 640
                if (-not $runnerReady) { throw 'Runner identity/readiness mismatch.' }
            } catch {
                $listener = Get-NetTCPConnection -LocalPort 9000 -State Listen -ErrorAction SilentlyContinue
                if ($listener) { throw 'Port 9000 is occupied but the expected research Runner is not ready. No process was killed.' }
                $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                $runnerScript = Join-Path $config.runnerDirectory 'scripts/start-runner.ps1'
                $arguments = '-NoProfile -File "' + $runnerScript + '" -ProductEnvPath "' + (Join-Path $repositoryRoot '.env') + '"'
                $runner = Start-Process pwsh -ArgumentList $arguments -WorkingDirectory $config.runnerDirectory -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $stateDirectory "runner-$stamp.stdout.log") -RedirectStandardError (Join-Path $stateDirectory "runner-$stamp.stderr.log")
                $runner.Id | Set-Content (Join-Path $stateDirectory 'runner-launcher.pid')
                throw 'Research Runner started; waiting for readiness.'
            }
            # A machine can have VPN, Ethernet, virtual, and WLAN adapters with gateways.
            # Advertise the address behind the active default route, rather than whichever
            # adapter PowerShell happens to enumerate first.
            $defaultRoute = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' |
                Where-Object { $_.NextHop -ne '0.0.0.0' } |
                Sort-Object RouteMetric, InterfaceMetric |
                Select-Object -First 1
            if ($null -eq $defaultRoute) { throw 'No active IPv4 default route for LAN advertisement.' }
            $address = Get-NetIPAddress -InterfaceIndex $defaultRoute.InterfaceIndex -AddressFamily IPv4 |
                Where-Object { $_.AddressState -eq 'Preferred' -and $_.IPAddress -notmatch '^(127|169\.254)\.' } |
                Select-Object -ExpandProperty IPAddress -First 1
            if (-not $address) { throw 'The active IPv4 default route has no preferred unicast address.' }
            if ($address -ne $lastAddress -or $null -eq $mdnsProcess -or $mdnsProcess.HasExited) {
                if ($null -ne $mdnsProcess -and -not $mdnsProcess.HasExited) { $mdnsProcess.Kill() }
                $mdnsScript = Join-Path $repositoryRoot 'test-support/lan-acceptance/mdns.cjs'
                $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                $mdnsProcess = Start-Process $config.nodePath -ArgumentList ('"' + $mdnsScript + '" ' + $address) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $stateDirectory "mdns-$stamp.stdout.log") -RedirectStandardError (Join-Path $stateDirectory "mdns-$stamp.stderr.log")
                $mdnsProcess.Id | Set-Content (Join-Path $stateDirectory 'mdns.pid')
                $lastAddress = $address
            }
            $compose = @('compose','-p','pig-inventory-p0','-f','docker-compose.yml','-f','docker-compose.runner-local.yml','-f','docker-compose.lan-acceptance.yml')
            if (-not $composeStarted) {
                & docker @compose up -d --no-build *> (Join-Path $stateDirectory 'compose-start.log')
                if ($LASTEXITCODE -ne 0) { throw 'Compose startup failed; inspect compose-start.log.' }
                $composeStarted = $true
            }
            $health = & curl.exe --silent --show-error --fail --ssl-revoke-best-effort --noproxy '*' --cacert (Join-Path $env:LAN_TLS_DIRECTORY 'ca.pem') --max-time 10 'https://pig-inventory.local:8443/actuator/health' 2> (Join-Path $stateDirectory 'https-health.stderr.log')
            if ($LASTEXITCODE -ne 0 -or ($health | ConvertFrom-Json).status -ne 'UP') { throw 'HTTPS health is not UP yet.' }
            $status = 'ready'
            [ordered]@{status=$status;verifiedAt=[DateTime]::UtcNow.ToString('o');address=$address;endpoint='https://pig-inventory.local:8443';runnerReady=$runnerReady;deviceAcceptance='pending'} |
                ConvertTo-Json | Set-Content (Join-Path $stateDirectory 'status.json')
        } catch {
            $composeStarted = $false
            $status = $_.Exception.Message
            [ordered]@{status='waiting';reason=$status;verifiedAt=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content (Join-Path $stateDirectory 'status.json')
        }
        if ($status -ne $lastStatus) { Write-Output ("[{0:o}] {1}" -f [DateTime]::UtcNow,$status); $lastStatus = $status }
        if ($Once) {
            if ($status -ne 'ready') { throw $status }
            break
        }
        Start-Sleep -Seconds 30
    } while ($true)
} finally {
    Pop-Location
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
