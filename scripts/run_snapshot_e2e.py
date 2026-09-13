"""Synthetic isolated recovery rehearsal; no P0 data, builds, or volume deletion."""
import base64
import hashlib
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
import uuid
from datetime import date
from pathlib import Path

import inventory_snapshot as snapshot

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "test-assets/generated/snapshot-recovery" / uuid.uuid4().hex[:12]
SOURCE = "pig-inventory-recovery-source-" + OUT.name
TARGET = "pig-inventory-recovery-target-" + OUT.name
BASE = "http://127.0.0.1:8096/api/v1/"
TOKEN = ""
VALUES = {
    "MYSQL_DATABASE": "pig_inventory", "MYSQL_USER": "pig_inventory",
    "MYSQL_PASSWORD": "synthetic-recovery-mysql", "MYSQL_ROOT_PASSWORD": "synthetic-recovery-root",
    "MINIO_ROOT_USER": "synthetic-recovery", "MINIO_ROOT_PASSWORD": "synthetic-recovery-minio",
    "MINIO_BUCKET": "pig-inventory", "SECURITY_ENABLED": "true", "SPRING_PROFILES_ACTIVE": "dev",
    "JWT_SIGNING_SECRET": base64.b64encode(b"synthetic-recovery-signing-key-only-20260912").decode(),
    "APP_BOOTSTRAP_ADMIN_USERNAME": "recovery-bootstrap", "APP_BOOTSTRAP_ADMIN_PASSWORD": "synthetic-recovery-bootstrap",
    "APP_BOOTSTRAP_ADMIN_DISPLAY_NAME": "Synthetic recovery", "APP_BOOTSTRAP_ORGANIZATION_CODE": "RECOVERY",
    "APP_BOOTSTRAP_ORGANIZATION_NAME": "Synthetic recovery", "APP_E2E_FIXTURES_ENABLED": "true",
    "APP_E2E_FIXTURE_PASSWORD": "synthetic-recovery-only", "INFERENCE_CALLBACK_TOKEN": "synthetic-recovery-callback",
    "INFERENCE_DISPATCHER_ENABLED": "false", "COUNTING_PROVIDER": "unavailable",
    "MODEL_RESEARCH_ENABLED": "false", "MODEL_APPROVED": "false", "MULTIVIEW_AUTO_COUNT_ENABLED": "false",
    "MODEL_KEY": "pending-license-review", "MODEL_VERSION": "unverified", "MODEL_CHECKSUM": "unverified",
    "MODEL_ADAPTER_VERSION": "http-v1", "YOLO_HTTP_ENDPOINT": "", "YOLO_HTTP_READY_ENDPOINT": "",
}


def compose(project, *args):
    if project not in (SOURCE, TARGET):
        raise ValueError("Rehearsal project is fixed")
    result = subprocess.run(["docker", "compose", "-p", project, "--env-file", str(OUT / "runtime.env"),
                             "-f", str(ROOT / "docker-compose.yml"), "-f", str(OUT / "overlay.yml"), *args],
                            env={**os.environ, **VALUES}, capture_output=True, text=True, encoding="utf-8")
    with (OUT / "compose.log").open("a", encoding="utf-8") as log:
        log.write(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(f"Isolated Compose {args[0]} failed; see generated compose.log")


def api(path, method="GET", body=None, headers=None, expected=200):
    request_headers = {"X-Idempotency-Key": str(uuid.uuid4())}
    if TOKEN:
        request_headers["Authorization"] = "Bearer " + TOKEN
    if isinstance(body, bytes):
        request_headers["Content-Type"] = "application/octet-stream"
    elif body is not None:
        request_headers["Content-Type"] = "application/json"
        body = json.dumps(body).encode()
    request_headers.update(headers or {})
    request = urllib.request.Request(BASE + path, data=body, headers=request_headers, method=method)
    try:
        response = urllib.request.urlopen(request, timeout=30)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        data = response.read()
        if response.status != expected:
            raise AssertionError(f"{method} {path.split('?')[0]}: expected {expected}, received {response.status}")
        if response.headers.get("Content-Type", "").startswith("application/json") and data:
            return json.loads(data)
        return data


def login():
    global TOKEN
    TOKEN = api("auth/login", "POST", {"username": "e2e-farm-admin", "password": VALUES["APP_E2E_FIXTURE_PASSWORD"]})["accessToken"]


def main():
    OUT.mkdir(parents=True)
    (OUT / "runtime.env").write_text("\n".join(f"{k}={v}" for k, v in VALUES.items()), encoding="utf-8")
    overlay = {"services": {}}
    for service, image in {"business-api": "business-api", "admin-web": "admin-web",
                           "inference-api": "inference-api", "inference-worker": "inference-api"}.items():
        # Resolve and pin the already verified candidate, never build/pull another version.
        image_id = snapshot.docker("image", "inspect", f"pig-inventory-functional-{image}:20260912-v13", "--format", "{{.Id}}")
        overlay["services"][service] = {"image": image_id, "pull_policy": "never"}
    # !override is necessary to remove the base gateway port entirely.
    (OUT / "overlay.yml").write_text("services:\n" + "".join(
        f"  {key}:\n    image: '{value['image']}'\n    pull_policy: never\n" for key, value in overlay["services"].items()) +
        "  gateway:\n    ports: !override\n      - '127.0.0.1:8096:80'\n", encoding="utf-8")
    success = False
    try:
        compose(SOURCE, "config", "--quiet")
        compose(SOURCE, "up", "-d", "--no-build", "--wait", "--wait-timeout", "240")
        print("Synthetic source ready; creating confirmed correction fixture.", flush=True)
        login()
        org = api("me")["activeOrganizationId"]
        building, pen, asset = [str(uuid.uuid4()) for _ in range(3)]
        for kind, identity, parent in [("buildings", building, org), ("pens", pen, building)]:
            api(f"master-data/{kind}/{identity}", "PUT", {"parentId": parent, "code": "RESTORE", "name": "Synthetic restore",
                "enabled": True, "expectedVersion": 0, "reason": "Synthetic recovery rehearsal"})
        package = api("upload-packages", "POST", {"clientPackageId": str(uuid.uuid4()), "organizationId": org,
                      "penId": pen, "businessDate": str(date.today()), "captureKind": "single"}, expected=201)
        media = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=") + uuid.uuid4().bytes
        sha = hashlib.sha256(media).hexdigest()
        path = "upload-packages/" + package["id"]
        api(path + "/blobs/" + asset, "PUT", media, {"X-Content-SHA256": sha}, expected=201)
        api(path + "/manifest", "PUT", {"captureSetId": str(uuid.uuid4()), "captureKind": "single", "penId": pen,
            "assets": [{"assetId": asset, "viewPosition": "single", "capturedAt": str(date.today()) + "T00:00:00Z",
            "originalName": "synthetic.png", "width": 1, "height": 1, "sha256": sha, "byteSize": len(media),
            "mediaType": "image/png", "exif": {}, "roi": None}]}, expected=201)
        committed = api(path + "/commit", "POST", expected=201)
        source_id = committed["sessionId"]
        api("inference-jobs/" + committed["inferenceJobId"] + "/result", "PUT", {
            "status": "failed", "count": None, "detections": [], "warnings": [],
            "modelKey": VALUES["MODEL_KEY"], "modelVersion": VALUES["MODEL_VERSION"],
            "modelChecksum": VALUES["MODEL_CHECKSUM"], "adapterVersion": "http-v1",
            "inferenceSource": "synthetic-recovery", "latencyMs": 0,
            "failureCode": "PROVIDER_TIMEOUT", "failureMessage": "Synthetic recovery fixture"},
            {"X-Inference-Service-Key": VALUES["INFERENCE_CALLBACK_TOKEN"]}, expected=204)
        api("inventory-sessions/" + source_id + "/confirm", "POST", {"confirmedCount": 17, "reason": "Synthetic manual confirmation"})
        corrected = api("inventory-sessions/" + source_id + "/corrections", "POST",
                        {"correctedCount": 19, "reason": "Synthetic correction"})
        before = api("inventory-sessions/" + corrected["id"])
        # Persist a synthetic Redis marker to verify queue storage is included.
        snapshot.docker("exec", SOURCE + "-redis-1", "redis-cli", "SET", "recovery:synthetic", "preserved")
        try:
            snapshot.backup(SOURCE, OUT / "must-not-exist")
            raise AssertionError("Live source must be rejected")
        except ValueError:
            assert not (OUT / "must-not-exist").exists()
        compose(SOURCE, "stop", "--timeout", "60")
        print("Source stopped; creating and restoring consistent three-volume snapshot.", flush=True)
        snapshot.backup(SOURCE, OUT / "snapshot")
        snapshot.restore(OUT / "snapshot", TARGET)
        try:
            snapshot.restore(OUT / "snapshot", TARGET)
            raise AssertionError("Existing target must be rejected")
        except ValueError:
            pass
        compose(TARGET, "up", "-d", "--no-build", "--wait", "--wait-timeout", "240")
        login()
        after = api("inventory-sessions/" + corrected["id"])
        historical = api("inventory-sessions/" + source_id)
        assert before == after, "Current confirmed session changed after restore"
        assert historical["status"] == "superseded" and historical["count"] == 17
        assert after["count"] == 19 and after["evidenceSessionId"] == source_id
        assert hashlib.sha256(api("media-assets/" + asset + "/content")).hexdigest() == sha
        assert api("inventory-sessions/" + corrected["id"] + "/media")[0]["locked"]
        api("media-assets/" + asset, "DELETE", expected=409)
        assert snapshot.docker("exec", TARGET + "-redis-1", "redis-cli", "GET", "recovery:synthetic") == "preserved"
        # Confirm corruption is detected before a target volume is created.
        archive = OUT / "snapshot/mysql_data.tar.gz"
        with archive.open("ab") as stream:
            stream.write(b"corruption-probe")
        try:
            snapshot.verify(OUT / "snapshot")
            raise AssertionError("Corrupt archive must be rejected")
        except ValueError:
            pass
        finally:
            with archive.open("r+b") as stream:
                stream.truncate(archive.stat().st_size - len(b"corruption-probe"))
        snapshot.verify(OUT / "snapshot")
        result = {"status": "passed", "sourceProject": SOURCE, "targetProject": TARGET,
                  "confirmedCount": 19, "historicalCount": 17, "mediaHashMatched": True,
                  "lockedDeleteStatus": 409, "redisRestored": True, "liveSourceRejected": True,
                  "existingTargetRejected": True, "corruptionRejected": True, "productionRecoveryVerified": False}
        (OUT / "summary.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(result), flush=True)
        success = True
    finally:
        # Never remove volumes, even after successful validation.
        if success:
            for project in (SOURCE, TARGET):
                compose(project, "down")
        else:
            print(f"Incomplete rehearsal preserved for diagnosis: {OUT}", file=sys.stderr)


if __name__ == "__main__":
    main()
