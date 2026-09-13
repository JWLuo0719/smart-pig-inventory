"""Cold local Compose volume snapshots. Never stops services or overwrites volumes.

The caller must stop the selected project in a maintenance window. Restoring
creates only a new project's volumes; service startup and business readback are
separate gates. Archives contain sensitive data and require protected storage.
"""
import argparse
import hashlib
import json
import re
import subprocess
import tarfile
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

VOLUMES = {"mysql_data": ("mysql", "/var/lib/mysql"),
           "redis_data": ("redis", "/data"), "minio_data": ("minio", "/data")}


def docker(*args):
    result = subprocess.run(["docker", *args], capture_output=True, text=True, encoding="utf-8")
    if result.returncode:
        # Docker errors can contain configuration. Keep stdout/stderr out of logs.
        raise RuntimeError(f"Docker {args[0]} failed (exit {result.returncode})")
    return result.stdout.strip()


def project_name(value):
    if not re.fullmatch(r"pig-inventory-[a-z0-9][a-z0-9-]{2,70}", value):
        raise ValueError("Expected an explicit pig-inventory-* project name")
    return value


def containers(project):
    ids = docker("ps", "-aq", "--filter", f"label=com.docker.compose.project={project}").split()
    return json.loads(docker("inspect", *ids)) if ids else []


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def check_archive(path):
    # Reject links/devices and path escape before granting a helper write access.
    with tarfile.open(path, "r:gz") as archive:
        count = 0
        for item in archive:
            name = PurePosixPath(item.name)
            if name.is_absolute() or ".." in name.parts or not (item.isfile() or item.isdir()):
                raise ValueError("Archive contains an unsupported or escaping entry")
            if item.isfile():
                with archive.extractfile(item) as stream:
                    while stream.read(1024 * 1024):
                        pass
            count += 1
        if not count:
            raise ValueError("Empty archive")


def helper_image():
    # Use an already installed image, resolve to its immutable ID, never pull.
    return docker("image", "inspect", "redis:7.4-alpine", "--format", "{{.Id}}")


def stopped_project(project):
    items = containers(project)
    if not items or any(c["State"]["Running"] for c in items):
        raise ValueError("All containers of the explicit source project must already be stopped")
    return items


def backup(project, output):
    items = stopped_project(project)
    image = helper_image()
    entries = []
    for logical, (service, destination) in VOLUMES.items():
        found = [c for c in items if c["Config"]["Labels"].get("com.docker.compose.service") == service]
        if len(found) != 1:
            raise ValueError(f"Expected exactly one {service} container")
        mounts = [m for m in found[0]["Mounts"] if m["Destination"] == destination]
        if len(mounts) != 1 or mounts[0]["Type"] != "volume":
            raise ValueError("Only the standard named-volume deployment is supported")
        volume = mounts[0]["Name"]
        info = json.loads(docker("volume", "inspect", volume))[0]
        labels = info.get("Labels") or {}
        if volume != f"{project}_{logical}" or labels.get("com.docker.compose.project") != project:
            raise ValueError("Volume ownership does not match source project")
        if docker("ps", "-q", "--filter", f"volume={volume}"):
            raise ValueError("A running container is using the source volume")
        entries.append({"logical": logical, "file": logical + ".tar.gz"})
    output.mkdir(parents=True, exist_ok=False)
    manifest = {"schemaVersion": 1, "sourceProject": project, "createdAt": datetime.now(timezone.utc).isoformat(),
                "mode": "all-services-stopped", "encrypted": False,
                "images": {c["Config"]["Labels"]["com.docker.compose.service"]: c["Image"] for c in items},
                "volumes": entries}
    for entry in entries:
        stopped_project(project)
        volume = f"{project}_{entry['logical']}"
        if docker("ps", "-q", "--filter", f"volume={volume}"):
            raise ValueError("Source volume became active during backup")
        docker("run", "--rm", "--network", "none", "--read-only", "--entrypoint", "tar",
               "--mount", f"type=volume,src={volume},dst=/source,readonly",
               "--mount", f"type=bind,src={output},dst=/backup", image,
               "--exclude=./mysql.sock", "-czpf", f"/backup/{entry['file']}", "-C", "/source", ".")
        path = output / entry["file"]
        check_archive(path)
        entry.update(sha256=digest(path), bytes=path.stat().st_size)
    stopped_project(project)
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return {"status": "snapshot-created", "volumes": len(entries), "runtimeVerified": False}


def verify(directory):
    manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
    if manifest.get("schemaVersion") != 1 or manifest.get("mode") != "all-services-stopped":
        raise ValueError("Unsupported snapshot manifest")
    entries = manifest["volumes"]
    if len(entries) != 3 or {e["logical"] for e in entries} != set(VOLUMES):
        raise ValueError("Snapshot must include all three data volumes")
    for entry in entries:
        if entry["file"] != entry["logical"] + ".tar.gz":
            raise ValueError("Invalid archive name")
        path = directory / entry["file"]
        if path.is_symlink() or path.stat().st_size != entry["bytes"] or digest(path) != entry["sha256"]:
            raise ValueError("Snapshot integrity mismatch")
        check_archive(path)
    return manifest


def restore(directory, target):
    manifest = verify(directory)
    if target == manifest["sourceProject"] or containers(target):
        raise ValueError("Restore requires a distinct project without containers")
    existing = set(docker("volume", "ls", "-q").split())
    names = [f"{target}_{key}" for key in VOLUMES]
    if existing.intersection(names):
        raise ValueError("Restore refuses existing target volumes, even when empty")
    image = helper_image()
    # No removal on failure: partial restore remains inspectable. Use a new target.
    for entry in manifest["volumes"]:
        logical = entry["logical"]
        name = f"{target}_{logical}"
        docker("volume", "create", "--label", f"com.docker.compose.project={target}",
               "--label", f"com.docker.compose.volume={logical}", name)
        docker("run", "--rm", "--network", "none", "--read-only", "--entrypoint", "tar",
               "--mount", f"type=volume,src={name},dst=/restore",
               "--mount", f"type=bind,src={directory},dst=/backup,readonly", image,
               "-xzpf", f"/backup/{entry['file']}", "-C", "/restore")
    return {"status": "volumes-restored", "targetProject": target, "runtimeVerified": False,
            "requiredImages": manifest["images"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("backup"); p.add_argument("--project", type=project_name, required=True); p.add_argument("--output", type=Path, required=True)
    p = sub.add_parser("verify"); p.add_argument("--snapshot", type=Path, required=True)
    p = sub.add_parser("restore"); p.add_argument("--snapshot", type=Path, required=True); p.add_argument("--target-project", type=project_name, required=True)
    args = parser.parse_args()
    if args.command == "backup": result = backup(args.project, args.output.resolve())
    elif args.command == "restore": result = restore(args.snapshot.resolve(), args.target_project)
    else:
        verify(args.snapshot.resolve()); result = {"status": "integrity-verified", "runtimeVerified": False}
    print(json.dumps(result))


if __name__ == "__main__":
    main()
