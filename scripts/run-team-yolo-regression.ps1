[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PythonPath,
    [Parameter(Mandatory = $true)][string]$DatasetRoot,
    [Parameter(Mandatory = $true)][string]$RunnerRepo,
    [Parameter(Mandatory = $true)][string]$Weights,
    [Parameter(Mandatory = $true)][string]$ExpectedChecksum,
    [string]$Thresholds = '0.25,0.40,0.50,0.60,0.65,0.70',
    [string]$Device = 'cpu',
    [int]$ImageSize = 640,
    [double]$IouThreshold = 0.7,
    [int]$MaxImages = 0,
    [string]$OutputDirectory,
    [string]$ReleaseModelKey,
    [string]$ReleaseModelVersion,
    [string]$ReleaseAdapterVersion = 'http-v1',
    [string]$RegressionBaseline
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$evaluator = Join-Path $PSScriptRoot 'evaluate_yolo_counting.py'
$releaseGate = Join-Path $PSScriptRoot 'model_release_gate.py'
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repositoryRoot 'test-assets\generated'
}

foreach ($requiredPath in @($PythonPath, $DatasetRoot, $RunnerRepo, $Weights, $evaluator)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required path does not exist: $requiredPath"
    }
}
if ([string]::IsNullOrWhiteSpace($ReleaseModelKey) -xor [string]::IsNullOrWhiteSpace($ReleaseModelVersion)) {
    throw 'ReleaseModelKey and ReleaseModelVersion must be provided together.'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$validationOutput = Join-Path $OutputDirectory 'team-yolo-calibration-val.json'
$testOutput = Join-Path $OutputDirectory 'team-yolo-evaluation-test.json'
$summaryOutput = Join-Path $OutputDirectory 'team-yolo-regression-summary.json'

function Invoke-Evaluation {
    param(
        [Parameter(Mandatory = $true)][string]$Split,
        [Parameter(Mandatory = $true)][string]$ThresholdValues,
        [Parameter(Mandatory = $true)][string]$OutputPath
    )

    $arguments = @(
        $evaluator,
        '--dataset-root', $DatasetRoot,
        '--runner-repo', $RunnerRepo,
        '--weights', $Weights,
        '--expected-checksum', $ExpectedChecksum,
        '--split', $Split,
        '--thresholds', $ThresholdValues,
        '--device', $Device,
        '--image-size', $ImageSize.ToString([Globalization.CultureInfo]::InvariantCulture),
        '--iou-threshold', $IouThreshold.ToString([Globalization.CultureInfo]::InvariantCulture),
        '--output', $OutputPath
    )
    if ($MaxImages -gt 0) {
        $arguments += @('--max-images', $MaxImages.ToString([Globalization.CultureInfo]::InvariantCulture))
    }
    & $PythonPath @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "YOLO evaluation failed for split: $Split"
    }
}

Write-Output '[INFO] Selecting a research threshold on the validation split'
Invoke-Evaluation -Split 'val' -ThresholdValues $Thresholds -OutputPath $validationOutput
$validation = Get-Content -LiteralPath $validationOutput -Raw | ConvertFrom-Json
$selectedThreshold = [double]$validation.lowest_mae_observed_in_split.threshold
$selectedText = $selectedThreshold.ToString([Globalization.CultureInfo]::InvariantCulture)

Write-Output '[INFO] Evaluating the selected threshold once on the test split'
Invoke-Evaluation -Split 'test' -ThresholdValues $selectedText -OutputPath $testOutput
$test = Get-Content -LiteralPath $testOutput -Raw | ConvertFrom-Json
$testMetric = @($test.metrics_by_threshold)[0]

$summary = [ordered]@{
    schema_version = 1
    created_at_utc = [DateTimeOffset]::UtcNow.ToString('o')
    policy = 'Read-only research evidence. This result does not approve production automatic counting.'
    threshold_selection = [ordered]@{
        split = 'val'
        candidate_thresholds = @($validation.metrics_by_threshold | ForEach-Object { $_.threshold })
        selected_threshold = $selectedThreshold
        selection_metric = 'lowest MAE, then lowest absolute bias, then lowest threshold'
        validation_result = $validation.lowest_mae_observed_in_split
    }
    held_out_evaluation = [ordered]@{
        split = 'test'
        threshold = $selectedThreshold
        result = $testMetric
        latency_ms = $test.latency_ms
    }
    model = $validation.model
    runtime = $validation.runtime
    limitations = @(
        'The current validation and test distributions are research data, not an authorized business gold set.',
        'The held-out test split has a narrow count distribution and cannot establish production generalization.',
        'Threshold or dependency changes require a new versioned report.'
    )
}

$summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryOutput -Encoding utf8
if (-not [string]::IsNullOrWhiteSpace($ReleaseModelKey)) {
    $manifestOutput = Join-Path $OutputDirectory 'team-yolo-release-manifest.json'
    & $PythonPath $releaseGate build-manifest `
        --summary $summaryOutput `
        --weights $Weights `
        --expected-checksum $ExpectedChecksum `
        --model-key $ReleaseModelKey `
        --model-version $ReleaseModelVersion `
        --adapter-version $ReleaseAdapterVersion `
        --output $manifestOutput
    if ($LASTEXITCODE -ne 0) {
        throw 'Research release manifest gate failed.'
    }
    if (-not [string]::IsNullOrWhiteSpace($RegressionBaseline)) {
        if (-not (Test-Path -LiteralPath $RegressionBaseline -PathType Leaf)) {
            throw "Regression baseline does not exist: $RegressionBaseline"
        }
        $driftOutput = Join-Path $OutputDirectory 'team-yolo-regression-drift-report.json'
        & $PythonPath $releaseGate compare `
            --summary $summaryOutput `
            --baseline $RegressionBaseline `
            --output $driftOutput
        if ($LASTEXITCODE -ne 0) {
            throw 'Regression drift gate failed.'
        }
    }
}
Write-Output ($summary | ConvertTo-Json -Depth 12 -Compress)
Write-Output "[OK] Local ignored summary: $summaryOutput"
