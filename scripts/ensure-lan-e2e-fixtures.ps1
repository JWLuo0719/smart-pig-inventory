[CmdletBinding()]
param(
    [string]$ComposeProjectName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $repositoryRoot '.env'

function Get-RequiredEnvValue {
    param([string]$Name)

    if (-not (Test-Path -LiteralPath $envFile)) {
        throw "Missing local configuration: $envFile. Run .\scripts\initialize-local-dev.ps1 first."
    }
    $pattern = "^$([regex]::Escape($Name))=(.+)$"
    $line = Get-Content -LiteralPath $envFile | Where-Object { $_ -match $pattern } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($line)) {
        throw "Missing $Name in local .env."
    }
    $value = $line -replace "^$([regex]::Escape($Name))=", ''
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Missing $Name in local .env."
    }
    return $value
}

try {
    $composePrefix = @('compose')
    if (-not [string]::IsNullOrWhiteSpace($ComposeProjectName)) {
        $composePrefix += @('-p', $ComposeProjectName)
    }

    $organizationCode = Get-RequiredEnvValue -Name 'APP_BOOTSTRAP_ORGANIZATION_CODE'
    if ($organizationCode -notmatch '^[A-Za-z0-9_-]{1,64}$') {
        throw 'APP_BOOTSTRAP_ORGANIZATION_CODE must contain only letters, numbers, underscores, or hyphens for this local fixture script.'
    }

    $escapedOrganizationCode = $organizationCode.Replace("'", "''")
    $organizationCheckSql = "SELECT COUNT(*) FROM farm_organization WHERE code = '$escapedOrganizationCode';"
    $organizationMatches = $organizationCheckSql | & docker @composePrefix exec -T mysql sh -lc 'mysql --batch --skip-column-names --silent -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"'
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not query MySQL. Start the Docker Compose stack and wait for the MySQL health check.'
    }
    if ([int]$organizationMatches -ne 1) {
        throw 'The bootstrap organization was not found. Confirm that security is enabled and the business-api has completed its first startup before creating fixtures.'
    }

    $sql = @"
START TRANSACTION;
SET @organization_code = '$escapedOrganizationCode';
SET @organization_id = (SELECT id FROM farm_organization WHERE code = @organization_code LIMIT 1);

SELECT COALESCE(MAX(sync_version), 0) + 1 INTO @next_sync_version
FROM (
    SELECT sync_version FROM farm_organization WHERE id = @organization_id
    UNION ALL
    SELECT sync_version FROM building WHERE organization_id = @organization_id
    UNION ALL
    SELECT p.sync_version FROM pen p JOIN building b ON b.id = p.building_id WHERE b.organization_id = @organization_id
) AS versions;

INSERT INTO building (id, organization_id, code, name, enabled, sync_version)
SELECT UUID_TO_BIN(UUID()), @organization_id, 'E2E-B01', 'E2E Synthetic Building', TRUE, @next_sync_version
WHERE @organization_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM building WHERE organization_id = @organization_id AND code = 'E2E-B01');

SET @building_id = (SELECT id FROM building WHERE organization_id = @organization_id AND code = 'E2E-B01' LIMIT 1);

INSERT INTO pen (id, building_id, code, name, enabled, sync_version)
SELECT UUID_TO_BIN(UUID()), @building_id, 'E2E-P01', 'E2E Synthetic Pen', TRUE, @next_sync_version + 1
WHERE @building_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM pen WHERE building_id = @building_id AND code = 'E2E-P01');

COMMIT;

SELECT o.code AS organization_code, b.code AS building_code, p.code AS pen_code
FROM farm_organization o
JOIN building b ON b.organization_id = o.id
JOIN pen p ON p.building_id = b.id
WHERE o.code = @organization_code AND b.code = 'E2E-B01' AND p.code = 'E2E-P01';
"@

    $sql | & docker @composePrefix exec -T mysql sh -lc 'mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"'
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not create E2E fixtures. Start the Docker Compose stack with security enabled, wait for MySQL and business-api health checks, then retry.'
    }
    Write-Output '[OK] Local synthetic E2E building and pen are ready. No credentials were displayed.'
}
catch {
    Write-Error $_
    exit 1
}
