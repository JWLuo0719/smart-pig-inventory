#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$directory=Join-Path $root 'tmp/joycode-tooling-check'
New-Item -ItemType Directory -Force -Path $directory | Out-Null
$settings=[ordered]@{
    MYSQL_URL='jdbc:mysql://fixture.internal:3306/competition'; MYSQL_USER='fixture'; MYSQL_PASSWORD=([guid]::NewGuid().ToString('N'))
    REDIS_HOST='fixture.internal'; MINIO_ENDPOINT='https://storage.fixture.org'; MINIO_ACCESS_KEY='fixture'; MINIO_SECRET_KEY=([guid]::NewGuid().ToString('N')); MINIO_BUCKET='fixture'
    JWT_SIGNING_SECRET=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([guid]::NewGuid().ToString('N')))
    CORS_ALLOWED_ORIGINS='https://judge.fixture.org'; INFERENCE_BASE_URL='https://inference.fixture.org'
    INFERENCE_CALLBACK_TOKEN=([guid]::NewGuid().ToString('N')); MONITORING_SERVICE_KEY=([guid]::NewGuid().ToString('N'))
    SECURITY_ENABLED='true'; SPRING_PROFILES_ACTIVE='prod'; APP_E2E_FIXTURES_ENABLED='false'
    MODEL_APPROVED='false'; MULTIVIEW_AUTO_COUNT_ENABLED='false'; VIDEO_AUTO_COUNT_ENABLED='false'
    ASSISTANT_ENABLED='true'; ASSISTANT_DATA_EGRESS_APPROVED='true'; ASSISTANT_MODEL_ENDPOINT='https://model.fixture.org/chat/completions'
    ASSISTANT_MODEL_NAME='fixture'; ASSISTANT_MODEL_API_KEY=([guid]::NewGuid().ToString('N'))
    COMPETITION_VIEWER_PROVISION_ENABLED='true'; COMPETITION_VIEWER_USERNAME='fixture-viewer'; COMPETITION_VIEWER_PASSWORD=([guid]::NewGuid().ToString('N'))
    COMPETITION_VIEWER_ORGANIZATION_CODE='FIXTURE'; COMPETITION_VIEWER_EXPIRES_AT=[DateTimeOffset]::UtcNow.AddDays(30).ToString('o')
}
$path=Join-Path $directory 'configuration.env'
function Save-Settings { $settings.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } | Set-Content -LiteralPath $path -Encoding utf8 }
Save-Settings
$valid=(& (Join-Path $root 'scripts/test-joycode-configuration.ps1') -EnvironmentFile $path) | ConvertFrom-Json
if ($valid.status -ne 'configuration-passed' -or $valid.deployed) { throw 'Positive configuration check failed' }
$cases=@(
    @{key='SECURITY_ENABLED'; value='false'}, @{key='MODEL_APPROVED'; value='true'},
    @{key='ASSISTANT_DATA_EGRESS_APPROVED'; value='false'}, @{key='ASSISTANT_MODEL_ENDPOINT'; value='http://remote.fixture.org/chat/completions'},
    @{key='CORS_ALLOWED_ORIGINS'; value='http://localhost:3000'}, @{key='MYSQL_PASSWORD'; value='short'},
    @{key='COMPETITION_VIEWER_EXPIRES_AT'; value='2020-01-01T00:00:00Z'}
)
foreach ($case in $cases) {
    $previous=$settings[$case.key]; $settings[$case.key]=$case.value; Save-Settings
    $rejected=$false
    try { & (Join-Path $root 'scripts/test-joycode-configuration.ps1') -EnvironmentFile $path | Out-Null } catch { $rejected=$true }
    $settings[$case.key]=$previous
    if (-not $rejected) { throw "Unsafe configuration was accepted: $($case.key)" }
}
Save-Settings
foreach ($file in @('package-joycode.ps1','test-joycode-configuration.ps1','test-joycode-tooling.ps1')) {
    $tokens=$null; $errors=$null
    [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root "scripts/$file"),[ref]$tokens,[ref]$errors) | Out-Null
    if ($errors.Count -gt 0) { throw "PowerShell syntax check failed: $file" }
}
[pscustomobject]@{status='passed';positive=1;rejected=$cases.Count;networkCalls=0;deployed=$false} | ConvertTo-Json
