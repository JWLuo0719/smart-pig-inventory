#Requires -Version 7.0
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# docker compose 的输出是 UTF-8；中文 Windows 默认 GBK 解码会吞掉 JSON 路径里的反斜杠。
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$root = Split-Path -Parent $PSScriptRoot

# 回归测试：只解析 Compose（docker compose config），不启动也不接触任何容器/卷。
# 覆盖四个修复点：生产端口摘除、runner-local 回环端口、模型旋钮注入、清单/示例补齐。
$work = Join-Path ([System.IO.Path]::GetTempPath()) ('pig-deploy-config-check-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$envFile = Join-Path $work 'placeholder.env'
@(
    'MYSQL_PASSWORD=placeholder-mysql-password-0123456789abcd'
    'MYSQL_ROOT_PASSWORD=placeholder-mysql-root-password-0123456789'
    'MINIO_ROOT_PASSWORD=placeholder-minio-root-password-0123456789'
    'RELEASE_INFERENCE_IMAGE=registry.invalid/pig/inference@sha256:' + ('0' * 64)
    'RELEASE_BUSINESS_IMAGE=registry.invalid/pig/business@sha256:' + ('0' * 64)
    'RELEASE_ADMIN_IMAGE=registry.invalid/pig/admin@sha256:' + ('0' * 64)
    'PUBLIC_BASE_URL=https://inventory.contoso-farm.test'
) | Set-Content -LiteralPath $envFile -Encoding utf8

$script:passed = 0
$script:failures = [Collections.Generic.List[string]]::new()
function Check {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    if ($Ok) {
        $script:passed++
        Write-Output "[OK] $Name"
    } else {
        $script:failures.Add("$Name :: $Detail")
        Write-Output "[FAIL] $Name :: $Detail"
    }
}

function Resolve-Compose {
    param([string[]]$ComposeFiles, [string]$Label)
    $json = & docker compose -p pig-inventory-deploy-check --env-file $envFile @ComposeFiles config --format json
    if ($LASTEXITCODE -ne 0) { throw "Compose cannot be resolved: $Label" }
    return ($json -join "`n") | ConvertFrom-Json -AsHashtable
}

try {
    $base = @('-f', (Join-Path $root 'docker-compose.yml'))
    $production = $base + @('-f', (Join-Path $root 'docker-compose.production.yml'))
    $runnerLocal = $base + @('-f', (Join-Path $root 'docker-compose.runner-local.yml'))

    & docker compose -p pig-inventory-deploy-check --env-file $envFile @base config --quiet
    Check 'base-compose-resolves' ($LASTEXITCODE -eq 0) 'docker compose config --quiet failed for the base file'

    $prod = Resolve-Compose -ComposeFiles $production -Label 'base+production'
    $runner = Resolve-Compose -ComposeFiles $runnerLocal -Label 'base+runner-local'

    # 1) 生产：minio 不再发布端口，且除 gateway（仅回环）外任何服务都不得发布端口。
    $prodMinioPorts = @()
    if ($prod.services.minio.ContainsKey('ports') -and $null -ne $prod.services.minio.ports) { $prodMinioPorts = @($prod.services.minio.ports) }
    Check 'production-minio-publishes-no-port' ($prodMinioPorts.Count -eq 0) ("minio still publishes: " + ($prodMinioPorts | ConvertTo-Json -Compress))
    $badPublish = @()
    foreach ($entry in $prod.services.GetEnumerator()) {
        if ($entry.Value.ContainsKey('ports') -and $null -ne $entry.Value.ports) {
            foreach ($port in $entry.Value.ports) {
                if (-not ($entry.Key -eq 'gateway' -and $port.host_ip -eq '127.0.0.1')) {
                    $badPublish += "$($entry.Key) publishes $($port.host_ip):$($port.published) -> $($port.target)"
                }
            }
        }
    }
    Check 'production-only-loopback-gateway-publishes' ($badPublish.Count -eq 0) ($badPublish -join '; ')

    # 2) runner-local：minio 只保留 127.0.0.1:9100->9000（!override 摘除 base 的 9000 全网卡发布）。
    $runnerMinioPorts = @($runner.services.minio.ports)
    Check 'runner-local-minio-single-loopback-port' ($runnerMinioPorts.Count -eq 1) ($runnerMinioPorts | ConvertTo-Json -Compress)
    $onlyLoopback = $runnerMinioPorts.Count -eq 1 -and
        $runnerMinioPorts[0].host_ip -eq '127.0.0.1' -and
        [string]$runnerMinioPorts[0].published -eq '9100' -and
        [string]$runnerMinioPorts[0].target -eq '9000'
    Check 'runner-local-minio-bound-to-9100-loopback' $onlyLoopback ($runnerMinioPorts | ConvertTo-Json -Compress)

    # 3) 模型旋钮注入：inference-api/inference-worker 七个旋钮 + business-api 的
    #    COUNTING_PROVIDER/OIDC_ISSUER_URI，默认值与 app/providers.py 代码默认一致。
    $knobs = [ordered]@{
        MULTIVIEW_DEDUP_ENABLED = 'false'
        MULTIVIEW_VIEW_OVERLAP = ''
        MULTIVIEW_CENTER_TOLERANCE = '0.08'
        MULTIVIEW_HEIGHT_TOLERANCE = '0.35'
        MULTIVIEW_MAX_COST = '1.0'
        VIDEO_COUNTING_ENABLED = 'false'
        VIDEO_MIN_TRACK_OBSERVATIONS = '1'
    }
    foreach ($service in @('inference-api', 'inference-worker')) {
        $settings = $prod.services[$service].environment
        $missing = @()
        foreach ($key in $knobs.Keys) {
            if (-not $settings.ContainsKey($key) -or [string]$settings[$key] -ne $knobs[$key]) {
                $missing += ("$key expected '$($knobs[$key])' got '$([string]$settings[$key])'")
            }
        }
        Check "$service-knobs-injected-with-code-defaults" ($missing.Count -eq 0) ($missing -join '; ')
    }
    $api = $prod.services.'business-api'.environment
    Check 'business-api-counting-provider-injected' ($api.ContainsKey('COUNTING_PROVIDER') -and [string]$api.COUNTING_PROVIDER -eq 'unavailable') ([string]$api.COUNTING_PROVIDER)
    Check 'business-api-oidc-issuer-uri-injected' ($api.ContainsKey('OIDC_ISSUER_URI')) ([string]$api.OIDC_ISSUER_URI)

    # 4) 清单与示例：requirements-runner.txt 提供 minio 客户端；两个 env 示例补齐
    #    三项合并标定并注明 Docker 下由 compose 注入；.env.example 备注可选 RUNNER_API_TOKEN。
    $requirements = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $root) 'pig-farm-agent/requirements-runner.txt') -Raw
    Check 'runner-requirements-list-minio' ($requirements -match '(?m)^minio>=7\.2\s*$') 'minio>=7.2 missing from requirements-runner.txt'
    foreach ($example in @((Join-Path $root '.env.example'), (Join-Path $root 'docs/deployment/production.env.example'))) {
        $text = Get-Content -LiteralPath $example -Raw
        $name = Split-Path -Leaf $example
        $missing = @()
        foreach ($key in @('MULTIVIEW_CENTER_TOLERANCE', 'MULTIVIEW_HEIGHT_TOLERANCE', 'MULTIVIEW_MAX_COST')) {
            if ($text -notmatch "(?m)^$key=") { $missing += $key }
        }
        Check "$name-multiview-calibration-listed" ($missing.Count -eq 0) ($missing -join ',')
        Check "$name-notes-compose-injection" ($text -match 'compose') "$name lacks the compose injection note"
    }
    $example = Get-Content -LiteralPath (Join-Path $root '.env.example') -Raw
    Check 'env-example-notes-runner-api-token' ($example -match 'RUNNER_API_TOKEN' -and $example -match 'X-Runner-Service-Key') 'RUNNER_API_TOKEN/X-Runner-Service-Key note missing from .env.example'
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:failures.Count -gt 0) {
    throw ("Deployment configuration regression failed: " + ($script:failures -join ' | '))
}
[pscustomobject]@{ status = 'configuration-passed'; checks = $script:passed; failures = $script:failures.Count } | ConvertTo-Json
