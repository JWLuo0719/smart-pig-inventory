[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$directory = Join-Path $env:LOCALAPPDATA 'PigInventory/lan-tls'
$caPath = Join-Path $directory 'ca.pem'
if (Test-Path -LiteralPath $directory) {
    foreach ($name in @('ca.pem','server.pem','server-key.pem')) {
        if (-not (Test-Path -LiteralPath (Join-Path $directory $name))) { throw 'Incomplete TLS directory. Inspect it; no automatic key replacement.' }
    }
    Write-Output '[OK] Existing LAN TLS identity preserved.'
    return
}
New-Item -ItemType Directory -Path $directory | Out-Null
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls.exe $directory /inheritance:r /grant:r "${identity}:(OI)(CI)F" 'SYSTEM:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Cannot restrict TLS directory ACL.' }
$rsaCa = [Security.Cryptography.RSA]::Create(3072)
$rsaServer = [Security.Cryptography.RSA]::Create(3072)
try {
    $hash = [Security.Cryptography.HashAlgorithmName]::SHA256
    $padding = [Security.Cryptography.RSASignaturePadding]::Pkcs1
    $caRequest = [Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=Pig Inventory LAN Acceptance CA', $rsaCa, $hash, $padding)
    $caRequest.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($true,$false,0,$true))
    $caRequest.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new([Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyCertSign,$true))
    $ca = $caRequest.CreateSelfSigned([DateTimeOffset]::UtcNow.AddMinutes(-5),[DateTimeOffset]::UtcNow.AddYears(3))
    $request = [Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=pig-inventory.local',$rsaServer,$hash,$padding)
    $san = [Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new()
    $san.AddDnsName('pig-inventory.local')
    $request.CertificateExtensions.Add($san.Build())
    $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($false,$false,0,$true))
    $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new([Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature -bor [Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyEncipherment,$true))
    $oids = [Security.Cryptography.OidCollection]::new()
    $null = $oids.Add([Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.1'))
    $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($oids,$true))
    $serial = [Security.Cryptography.RandomNumberGenerator]::GetBytes(16)
    $cert = $request.Create($ca,[DateTimeOffset]::UtcNow.AddMinutes(-5),[DateTimeOffset]::UtcNow.AddDays(90),$serial)
    $ca.ExportCertificatePem() | Set-Content -LiteralPath $caPath -Encoding ascii
    $cert.ExportCertificatePem() | Set-Content -LiteralPath (Join-Path $directory 'server.pem') -Encoding ascii
    $rsaServer.ExportPkcs8PrivateKeyPem() | Set-Content -LiteralPath (Join-Path $directory 'server-key.pem') -Encoding ascii
    # No root private key is persisted: this CA can only authenticate the issued leaf.
    [ordered]@{host='pig-inventory.local';port=8443;expires=$cert.NotAfter.ToUniversalTime().ToString('o');rootKeyPersisted=$false} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $directory 'identity.json')
    Write-Output '[OK] Private LAN certificate created for pig-inventory.local (90 days). No system trust store changed.'
} finally {
    $rsaCa.Dispose()
    $rsaServer.Dispose()
}
