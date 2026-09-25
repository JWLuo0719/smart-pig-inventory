from __future__ import annotations

import os
from uuid import UUID

import httpx

from .schemas import CountingJobResult


class TransientCallbackError(RuntimeError):
    pass


class PermanentCallbackError(RuntimeError):
    pass


def deliver_result(job_id: UUID, result: CountingJobResult) -> None:
    base_url = os.getenv("BUSINESS_API_BASE_URL", "http://localhost:8080").rstrip("/")
    callback_token = os.getenv("INFERENCE_CALLBACK_TOKEN", "")
    if not callback_token:
        # 空令牌 fail-closed：省略头发出去必然换来业务侧 401，白白制造一次永久失败；
        # 与业务侧校验口径、README 合同保持一致，配置修复前拒绝发送。
        raise PermanentCallbackError("INFERENCE_CALLBACK_TOKEN is empty; refusing to send the result callback")
    payload = {
        "status": result.status,
        "count": result.count,
        "detections": [
            {
                "assetId": str(detection.asset_id),
                "bbox": list(detection.bbox),
                "confidence": detection.confidence,
                "classId": detection.class_id,
            }
            for detection in result.detections
        ],
        "warnings": result.warnings,
        "modelKey": result.model_key,
        "modelVersion": result.model_version,
        "modelChecksum": result.model_checksum,
        "adapterVersion": result.adapter_version,
        "inferenceSource": result.inference_source,
        "latencyMs": result.latency_ms,
        "failureCode": result.failure_code,
        "failureMessage": result.failure_message,
    }
    # 空令牌已在上方 fail-closed，此处令牌必然非空，服务密钥头必须携带。
    headers = {
        "X-Idempotency-Key": str(job_id),
        "X-Inference-Service-Key": callback_token,
    }
    try:
        response = httpx.put(
            f"{base_url}/api/v1/inference-jobs/{job_id}/result",
            json=payload,
            headers=headers,
            timeout=httpx.Timeout(20.0, connect=5.0),
        )
    except httpx.RequestError as exception:
        raise TransientCallbackError(str(exception)) from exception
    if response.status_code in (200, 204):
        return
    if response.status_code >= 500 or response.status_code == 429:
        raise TransientCallbackError(f"callback returned {response.status_code}")
    raise PermanentCallbackError(f"callback returned {response.status_code}: {response.text[:500]}")
