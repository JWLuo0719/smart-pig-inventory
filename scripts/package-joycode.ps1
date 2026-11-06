#Requires -Version 7.0
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$output = Join-Path $root "artifacts/joycode/$stamp"
$stage = Join-Path $output 'source'
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$files = [System.Collections.Generic.List[string]]::new()
foreach ($folder in @('services/business-api/src/main', 'apps/admin-web/src', 'apps/admin-web/public', 'deployment/joycode')) {
    Get-ChildItem -LiteralPath (Join-Path $root $folder) -File -Recurse | ForEach-Object {
        $files.Add([IO.Path]::GetRelativePath($root, $_.FullName))
    }
}
foreach ($file in @('services/business-api/pom.xml', 'apps/admin-web/package.json', 'apps/admin-web/pnpm-lock.yaml', 'apps/admin-web/pnpm-workspace.yaml', 'apps/admin-web/next.config.ts', 'apps/admin-web/tsconfig.json', 'apps/admin-web/next-env.d.ts', 'apps/admin-web/eslint.config.mjs', 'scripts/package-joycode.ps1', 'scripts/test-joycode-configuration.ps1', 'scripts/test-joycode-tooling.ps1')) {
    if (Test-Path -LiteralPath (Join-Path $root $file)) { $files.Add($file) }
}
$manifest = @()
foreach ($file in $files) {
    if ($file -match '(^|[\\/])(\.env($|\.)|node_modules|target|build|artifacts|test-assets)([\\/]|$)' -or $file -match '\.(pt|pth|onnx|p12|jks|pem|key|log)$') { throw 'Unapproved file in cloud source bundle' }
    if ($file -match '\.sql$' -and $file.Replace('\','/') -notmatch '^services/business-api/src/main/resources/db/migration/V[0-9]+__[^/]+\.sql$') { throw 'Only versioned migration SQL may enter the cloud bundle' }
    $source = Join-Path $root $file
    $target = Join-Path $stage $file
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $target
    $manifest += [ordered]@{ path = $file.Replace('\','/'); sha256 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() }
}
Copy-Item -LiteralPath (Join-Path $root 'deployment/joycode/Dockerfile') -Destination (Join-Path $stage 'Dockerfile')
@'
**/node_modules
**/.next
**/target
**/.env
**/.env.*
**/*.pt
**/*.pth
**/*.onnx
**/*.pem
**/*.key
**/*.jks
**/*.p12
**/*.log
.git
'@ | Set-Content -LiteralPath (Join-Path $stage '.dockerignore') -Encoding utf8
foreach ($generated in @('Dockerfile','.dockerignore')) {
    $manifest += [ordered]@{ path=$generated; sha256=(Get-FileHash -LiteralPath (Join-Path $stage $generated) -Algorithm SHA256).Hash.ToLowerInvariant() }
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'source-manifest.json') -Encoding utf8
Copy-Item -LiteralPath (Join-Path $output 'source-manifest.json') -Destination (Join-Path $stage 'source-manifest.json')
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath (Join-Path $output 'joycode-source.zip')
[pscustomobject]@{ status='source-bundle-created'; source=$stage; zip=(Join-Path $output 'joycode-source.zip'); files=$manifest.Count; containerBuilt=$false; deployed=$false } | ConvertTo-Json
