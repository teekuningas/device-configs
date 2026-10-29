#!/usr/bin/env python3
"""Create initial ZNC credentials on miaucloud without printing them."""

import json
import os
from pathlib import Path
import pwd
import re
import secrets
import subprocess


IMAGE = (
    "docker.io/library/znc@sha256:"
    "5feabfc6dbf5504d3620cd9142e5bd85b338dc7605c4e0bc5c9025e3eab8c9f0"
)


def private_json(path, value, uid, gid):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as output:
        os.fchown(output.fileno(), uid, gid)
        json.dump(value, output)
        output.write("\n")
        output.flush()
        os.fsync(output.fileno())


def main():
    if os.geteuid() != 0:
        raise RuntimeError("Run as root on miaucloud")
    secret_file = Path("/var/data/.secrets/znc.json")
    account = pwd.getpwnam("zairex")
    client_directory = Path(account.pw_dir) / ".config/znc"
    client_file = client_directory / "client.json"
    if secret_file.exists() or client_file.exists():
        raise RuntimeError("Initial credentials already exist; do not rotate the savebuff key")
    if client_directory.is_symlink():
        raise RuntimeError("Refusing a symlinked client credential directory")
    metadata = secret_file.parent.stat()
    if metadata.st_uid != 0 or metadata.st_mode & 0o077:
        raise RuntimeError("Secret directory must be root-owned and private")
    password = secrets.token_urlsafe(32)
    result = subprocess.run(
        [
            "podman", "run", "--rm", "-i", "--network=none",
            "--user=100:65533", "--read-only", "--cap-drop=ALL",
            "--security-opt=no-new-privileges",
            "--entrypoint=/opt/znc/bin/znc", IMAGE, "--makepass",
        ],
        input=(password + "\n" + password + "\n").encode(),
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30,
    )
    if result.returncode:
        raise RuntimeError("Official ZNC password generator failed; no credentials installed")
    match = re.search(rb"Hash = (\$argon2id\$[^\r\n\x00]+)", result.stdout)
    if match is None:
        raise RuntimeError("Official ZNC password generator did not return an Argon2id hash")
    client_directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chown(client_directory, account.pw_uid, account.pw_gid)
    client_directory.chmod(0o700)
    private_json(secret_file, {
        "passwordHash": match.group(1).decode("ascii"),
        "savebuffKey": secrets.token_hex(32),
    }, 0, 0)
    private_json(client_file, {
        "host": "miaucloud-nixos.tail5b278e.ts.net",
        "port": 6697,
        "user": "zairex",
        "password": password,
    }, account.pw_uid, account.pw_gid)
    print("Initial Argon2id login and savebuff key installed privately.")
    print("Client credentials: " + str(client_file))


if __name__ == "__main__":
    main()
