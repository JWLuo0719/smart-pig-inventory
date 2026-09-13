# Run once in an Administrator PowerShell. No public-network rule is created.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$rules = @(
    @{Name='PigInventory-LAN-HTTPS';Protocol='TCP';Port=8443},
    @{Name='PigInventory-LAN-mDNS';Protocol='UDP';Port=5353}
)
foreach ($rule in $rules) {
    if (-not (Get-NetFirewallRule -Name $rule.Name -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name $rule.Name -DisplayName $rule.Name -Direction Inbound -Action Allow -Profile Private -RemoteAddress LocalSubnet -Protocol $rule.Protocol -LocalPort $rule.Port -ErrorAction Stop | Out-Null
    }
    $actual = Get-NetFirewallRule -Name $rule.Name -ErrorAction SilentlyContinue
    if ($null -eq $actual -or $actual.Enabled -ne 'True' -or $actual.Action -ne 'Allow') { throw 'Firewall rule creation/readback failed. Run this script as Administrator.' }
}
Write-Output '[OK] Private-network, local-subnet HTTPS/mDNS rules are configured.'
