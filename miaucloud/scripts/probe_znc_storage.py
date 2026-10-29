#!/usr/bin/env python3
"""Run as root on miaucloud; use only disposable, network-isolated ZNC state."""

import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys
import tempfile
import time
import uuid


IMAGE = (
    "docker.io/library/znc@sha256:"
    "5feabfc6dbf5504d3620cd9142e5bd85b338dc7605c4e0bc5c9025e3eab8c9f0"
)
BASE = 200000 + 20 * 65536
UID = 100
GID = 65533


def podman(*arguments, data=None):
    return subprocess.run(
        ["podman", *arguments],
        input=data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
        timeout=60,
    ).stdout


def main():
    if os.geteuid() != 0:
        raise RuntimeError("Run on miaucloud with sudo, not rootless Podman")
    podman("image", "exists", IMAGE)
    existing = podman("ps", "--all", "--quiet").decode().split()
    if existing:
        for container in json.loads(podman("inspect", *existing)):
            mappings = container["HostConfig"].get("IDMappings") or {}
            for kind in ("UidMap", "GidMap"):
                for mapping in mappings.get(kind) or []:
                    _, start, size = map(int, mapping.split(":"))
                    end = start + size
                    if start < BASE + 65536 and BASE < end:
                        raise RuntimeError("Namespace range overlaps an existing container")

    name = "irc-storage-probe-" + uuid.uuid4().hex[:12]
    root = Path(tempfile.mkdtemp(prefix=name + "-", dir="/var/data"))
    state = root / "state"
    checks = []
    try:
        state.mkdir(mode=0o700)
        os.chown(state, BASE + UID, BASE + GID)
        options = [
            "--network=none",
            f"--uidmap=0:{BASE}:65536",
            f"--gidmap=0:{BASE}:65536",
            f"--user={UID}:{GID}",
            "--read-only",
            "--cap-drop=ALL",
            "--security-opt=no-new-privileges",
            "--memory=128m",
            "--pids-limit=64",
            "--tmpfs=/tmp:rw,nosuid,nodev,size=16m,mode=1777",
            f"--volume={state}:/znc-data",
        ]
        password_hash = hashlib.sha256(secrets.token_bytes(32)).hexdigest()
        configuration = f"""Version = 1.10.3
SSLCertFile = /znc-data/cert.pem
SSLKeyFile = /znc-data/key.pem
<Listener private>
    Port = 16697
    IPv4 = true
    IPv6 = false
    SSL = true
    AllowIRC = true
    AllowWeb = false
</Listener>
<User storageprobe>
    Nick = storageprobe
    Ident = storageprobe
    RealName = Storage probe
    <Pass password>
        Method = sha256
        Hash = {password_hash}
    </Pass>
    <Network disconnected>
        IRCConnectEnabled = false
    </Network>
</User>
"""
        setup = """set -eu
umask 077
mkdir /znc-data/configs
openssl req -x509 -newkey rsa:2048 -noenc -days 1 -subj /CN=znc.storage.test -addext subjectAltName=DNS:znc.storage.test -keyout /znc-data/key.pem -out /znc-data/cert.pem >/tmp/keygen.out 2>&1
printf 'persistent marker\\n' > /znc-data/storage-marker
cat > /znc-data/configs/znc.conf <<'CONFIG'
""" + configuration + "CONFIG\n"
        podman(
            "run", "--rm", "-i", "--name=" + name, *options,
            "--entrypoint=/bin/sh", IMAGE, "-s", data=setup.encode(),
        )
        for phase in ("initial", "recreated"):
            podman("run", "-d", "--name=" + name, *options, IMAGE)
            for attempt in range(30):
                info = json.loads(podman("inspect", name))[0]
                if not info["State"]["Running"]:
                    raise RuntimeError("Synthetic ZNC failed to remain running")
                try:
                    podman(
                        "exec", "-i", name, "openssl", "s_client", "-quiet",
                        "-no_ign_eof",
                        "-connect", "127.0.0.1:16697",
                        "-verify_hostname", "znc.storage.test",
                        "-CAfile", "/znc-data/cert.pem", "-verify_return_error",
                        data=b"",
                    )
                except subprocess.CalledProcessError:
                    if attempt == 29:
                        raise
                    time.sleep(0.2)
                    continue
                break
            if info["HostConfig"]["NetworkMode"] != "none":
                raise RuntimeError("Unexpected container network")
            if info["HostConfig"].get("PortBindings"):
                raise RuntimeError("Unexpected published ports")
            pid = info["State"]["Pid"]
            if Path(f"/proc/{pid}").stat().st_uid != BASE + UID:
                raise RuntimeError("Unexpected host process UID")
            status = Path(f"/proc/{pid}/status").read_text()
            fields = dict(line.split(":", 1) for line in status.splitlines() if ":" in line)
            if fields["CapEff"].strip() != "0000000000000000":
                raise RuntimeError("Container process retained effective capabilities")
            if fields["NoNewPrivs"].strip() != "1":
                raise RuntimeError("Container process lacks no-new-privileges")
            if not info["HostConfig"]["ReadonlyRootfs"]:
                raise RuntimeError("Container root filesystem is writable")
            podman("stop", "--time=10", name)
            podman("rm", name)
            if (state / "storage-marker").read_text() != "persistent marker\n":
                raise RuntimeError("Persistent marker changed")
            if not (state / "configs/znc.conf").is_file():
                raise RuntimeError("ZNC configuration disappeared")
            for path in (state, *state.rglob("*")):
                stat = path.stat()
                if (stat.st_uid, stat.st_gid) != (BASE + UID, BASE + GID):
                    raise RuntimeError("Unexpected state ownership")
                if stat.st_mode & 0o077:
                    raise RuntimeError("State accessible to group or other users")
            checks.append(phase + ": verified TLS listener, mapped UID, restricted process, private persistent state")
        print(json.dumps({
            "image": IMAGE,
            "namespace_index": 20,
            "host_uid": BASE + UID,
            "host_gid": BASE + GID,
            "checks": checks,
            "mount": "plain bind; explicit mapped ownership; no :U or :idmap",
            "limitations": "No upstream connections, ident, real certificates, or production state",
        }, indent=2), flush=True)
    finally:
        exists = subprocess.run(
            ["podman", "container", "exists", name],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=30,
        )
        if exists.returncode == 0:
            podman("rm", "--force", name)
        elif exists.returncode != 1:
            raise RuntimeError("Could not check probe container cleanup")
        shutil.rmtree(root)
        print("Disposable probe container and state removed.", flush=True)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        print(error.stderr.decode(), file=sys.stderr)
        raise
