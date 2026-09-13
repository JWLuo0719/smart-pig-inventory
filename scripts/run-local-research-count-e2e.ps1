[CmdletBinding()]
param(
    [string]$ComposeProjectName = 'pig-inventory-p0',
    [string]$BaseUrl = 'http://127.0.0.1:8089/api/v1',
    [Parameter(Mandatory = $true)][string]$ImagePath,
    [string]$PenCode = 'E2E-P01',
    [int]$ExpectedCandidateCount = -1,
    [string]$ExpectedFailureCode = '',
    [int]$TimeoutSeconds = 180
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $repositoryRoot '.env'

function Get-EnvValue {
    param([string]$Name)

    $pattern = '^' + [regex]::Escape($Name) + '=(.*)$'
    $line = Get-Content -LiteralPath $envFile | Where-Object { $_ -match $pattern } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($line)) {
        throw "Missing environment value: $Name"
    }
    $value = $line -replace ('^' + [regex]::Escape($Name) + '='), ''
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Missing environment value: $Name"
    }
    return $value
}

function New-IdempotencyHeaders {
    param([string]$AccessToken)

    return @{
        Authorization = "Bearer $AccessToken"
        'X-Idempotency-Key' = [guid]::NewGuid().ToString()
    }
}

function Get-OptionalPropertyValue {
    param(
        [object]$Object,
        [string]$Name
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

try {
    if ($ComposeProjectName -notin @('pig-inventory-p0', 'pig-inventory-p1-fault', 'pig-inventory-p1-retry')) {
        throw 'This test may only target an approved isolated E2E Compose project.'
    }
    if (-not (Test-Path -LiteralPath $envFile)) {
        throw 'The local product .env file is missing.'
    }
    $resolvedImagePath = [IO.Path]::GetFullPath($ImagePath)
    if (-not (Test-Path -LiteralPath $resolvedImagePath -PathType Leaf)) {
        throw 'The research test image was not found.'
    }

    $password = Get-EnvValue -Name 'APP_E2E_FIXTURE_PASSWORD'
    $loginBody = @{ username = 'e2e-operator'; password = $password } | ConvertTo-Json -Depth 4
    $login = Invoke-RestMethod -Method Post -Uri "$BaseUrl/auth/login" `
        -Headers @{ 'X-Idempotency-Key' = [guid]::NewGuid().ToString() } `
        -ContentType 'application/json' -Body $loginBody
    $accessToken = $login.accessToken
    if ([string]::IsNullOrWhiteSpace($accessToken)) {
        throw 'Login did not return an access token.'
    }

    $authHeaders = @{ Authorization = "Bearer $accessToken" }
    $me = Invoke-RestMethod -Uri "$BaseUrl/me" -Headers $authHeaders
    $masterData = Invoke-RestMethod -Uri "$BaseUrl/master-data/changes" -Headers $authHeaders
    $pen = @($masterData.pens | Where-Object { $_.code -eq $PenCode })
    if ($pen.Count -ne 1) {
        throw "Expected exactly one enabled synthetic pen with code $PenCode."
    }

    Add-Type -AssemblyName System.Drawing.Common
    $image = [System.Drawing.Image]::FromFile($resolvedImagePath)
    try {
        $width = $image.Width
        $height = $image.Height
    }
    finally {
        $image.Dispose()
    }

    $imageBytes = [IO.File]::ReadAllBytes($resolvedImagePath)
    $shaBytes = [Security.Cryptography.SHA256]::HashData($imageBytes)
    $sha256 = [Convert]::ToHexString($shaBytes).ToLowerInvariant()
    $clientPackageId = [guid]::NewGuid()
    $assetId = [guid]::NewGuid()
    $captureSetId = [guid]::NewGuid()
    $createBody = [ordered]@{
        clientPackageId = $clientPackageId
        organizationId = $me.activeOrganizationId
        penId = $pen[0].id
        businessDate = (Get-Date).ToString('yyyy-MM-dd')
        captureKind = 'single'
    } | ConvertTo-Json -Depth 6
    $package = Invoke-RestMethod -Method Post -Uri "$BaseUrl/upload-packages" `
        -Headers (New-IdempotencyHeaders -AccessToken $accessToken) `
        -ContentType 'application/json' -Body $createBody

    $blobHeaders = New-IdempotencyHeaders -AccessToken $accessToken
    $blobHeaders['X-Content-SHA256'] = $sha256
    Invoke-WebRequest -Method Put -Uri "$BaseUrl/upload-packages/$($package.id)/blobs/$assetId" `
        -Headers $blobHeaders -ContentType 'application/octet-stream' -InFile $resolvedImagePath | Out-Null

    $manifestBody = [ordered]@{
        captureSetId = $captureSetId
        captureKind = 'single'
        penId = $pen[0].id
        assets = @([ordered]@{
            assetId = $assetId
            viewPosition = 'single'
            capturedAt = [DateTimeOffset]::UtcNow.ToString('o')
            originalName = [IO.Path]::GetFileName($resolvedImagePath)
            width = $width
            height = $height
            sha256 = $sha256
            perceptualHash = $null
            byteSize = $imageBytes.Length
            mediaType = 'image/jpeg'
            exif = @{}
            roi = $null
        })
    } | ConvertTo-Json -Depth 10
    Invoke-WebRequest -Method Put -Uri "$BaseUrl/upload-packages/$($package.id)/manifest" `
        -Headers (New-IdempotencyHeaders -AccessToken $accessToken) `
        -ContentType 'application/json' -Body $manifestBody | Out-Null

    $commitHeaders = New-IdempotencyHeaders -AccessToken $accessToken
    $commit = Invoke-RestMethod -Method Post -Uri "$BaseUrl/upload-packages/$($package.id)/commit" -Headers $commitHeaders
    $replayedCommit = Invoke-RestMethod -Method Post -Uri "$BaseUrl/upload-packages/$($package.id)/commit" -Headers $commitHeaders
    if ($commit.inferenceJobId -ne $replayedCommit.inferenceJobId) {
        throw 'Commit replay returned a different inference job.'
    }

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    $session = $null
    do {
        $session = Invoke-RestMethod -Uri "$BaseUrl/inventory-sessions/$($commit.sessionId)" -Headers $authHeaders
        if ($session.status -in @('review_required', 'confirmed')) {
            break
        }
        Start-Sleep -Seconds 2
    } while ([DateTimeOffset]::UtcNow -lt $deadline)

    if ($null -eq $session -or $session.status -ne 'review_required') {
        $actualStatus = if ($null -eq $session) { 'missing' } else { $session.status }
        throw "Research inference did not reach review_required. Actual status: $actualStatus"
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedFailureCode)) {
        if ($session.inferenceStatus -ne 'failed') {
            throw "Expected terminal inference failure. Actual inference status: $($session.inferenceStatus)."
        }
        if ($session.failureCode -ne $ExpectedFailureCode) {
            throw "Unexpected failure code. Expected $ExpectedFailureCode, got $($session.failureCode)."
        }
        $failedBusinessCount = Get-OptionalPropertyValue -Object $session -Name 'count'
        $failedCandidateCount = Get-OptionalPropertyValue -Object $session -Name 'rawModelCount'
        if (($null -ne $failedBusinessCount) -or ($null -ne $failedCandidateCount)) {
            throw 'A failed inference must not expose a candidate or business count.'
        }
        if ([string]::IsNullOrWhiteSpace($session.failureMessage)) {
            throw 'A failed inference did not expose a safe failure message.'
        }
    }
    else {
        if ($null -eq $session.rawModelCount) {
            throw 'Research single-image inference did not expose a candidate count.'
        }
        if (($ExpectedCandidateCount -ge 0) -and ($session.rawModelCount -ne $ExpectedCandidateCount)) {
            throw "Unexpected candidate count. Expected $ExpectedCandidateCount, got $($session.rawModelCount)."
        }
    }
    $expectedChecksum = Get-EnvValue -Name 'MODEL_CHECKSUM'
    if ($session.model.checksum -ne $expectedChecksum) {
        throw 'The stored model checksum does not match the configured team weight.'
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedFailureCode)) {
        Write-Output "[OK] Research count E2E reached safe manual review with failure $($session.failureCode)."
    }
    else {
        Write-Output "[OK] Research count E2E reached review_required with candidate count $($session.rawModelCount)."
    }
    Write-Output "[OK] Commit replay preserved inference job $($commit.inferenceJobId)."
    Write-Output "[OK] Stored model identity: $($session.model.modelKey) $($session.model.version) $($session.model.checksum)."
}
catch {
    Write-Error $_
    exit 1
}
