#!/usr/bin/env python3
"""Install Nix-owned ZNC structure with private runtime credentials."""

import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile


def private_json(path):
    metadata = path.lstat()
    if not stat.S_ISREG(metadata.st_mode):
        raise ValueError("ZNC secrets must be regular files")
    mode = stat.S_IMODE(metadata.st_mode)
    owner_private = metadata.st_uid == os.geteuid() and mode in (0o400, 0o600)
    credentials_directory = os.environ.get("CREDENTIALS_DIRECTORY")
    # systemd may retain root ownership and grant service access through an ACL.
    systemd_private = (
        credentials_directory is not None
        and path.parent == Path(credentials_directory)
        and metadata.st_uid == 0
        and metadata.st_gid == 0
        and mode == 0o440
    )
    if not (owner_private or systemd_private):
        raise ValueError("ZNC secrets must be owner-private (0400 or 0600) or root-owned systemd credentials")
    return json.loads(path.read_text())


def registry(values):
    def encode(value):
        return "".join(
            chr(byte) if 48 <= byte <= 57 or 65 <= byte <= 90 or 97 <= byte <= 122
            else f"%{byte:02x};"
            for byte in value.encode("utf-8")
        )

    return "".join(f"{encode(key)} {encode(value)}\n" for key, value in sorted(values.items()))


def atomic_write(target, text):
    fd, temporary = tempfile.mkstemp(prefix=".znc-", dir=target.parent)
    try:
        with os.fdopen(fd, "w") as output:
            output.write(text)
            output.flush()
            os.fchmod(output.fileno(), 0o600)
            os.fsync(output.fileno())
        os.replace(temporary, target)
    finally:
        Path(temporary).unlink(missing_ok=True)


def render(template, secret_file, target, network_count, sasl_files=()):
    secrets = private_json(secret_file)
    password_hash = secrets["passwordHash"]
    savebuff_key = secrets["savebuffKey"]
    if not isinstance(password_hash, str) or not re.fullmatch(
        r"\$argon2id\$v=19\$m=\d+,t=\d+,p=\d+\$[A-Za-z0-9+/]+\$[A-Za-z0-9+/]+",
        password_hash,
    ):
        raise ValueError("Invalid ZNC Argon2id password hash")
    if not isinstance(savebuff_key, str) or not re.fullmatch(r"[a-f0-9]{64}", savebuff_key):
        raise ValueError("Invalid ZNC savebuff key")
    text = template.read_text()
    if network_count < 1 or text.count("@PASSWORD_HASH@") != 1 or text.count("@SAVEBUFF_KEY@") != network_count:
        raise ValueError("Unexpected ZNC credential placeholders")
    text = text.replace("@PASSWORD_HASH@", password_hash).replace("@SAVEBUFF_KEY@", savebuff_key)
    registries = []
    for sasl_file, sasl_target in sasl_files:
        sasl = private_json(sasl_file)
        for key in ("username", "password"):
            value = sasl[key]
            if not isinstance(value, str) or not value or any(ord(c) < 32 or ord(c) == 127 for c in value):
                raise ValueError("Invalid SASL " + key)
        if any(c.isspace() for c in sasl["username"]):
            raise ValueError("Invalid SASL username")
        registries.append((sasl_target, registry({
            "username": sasl["username"],
            "password": sasl["password"],
            "mechanisms": "PLAIN",
            "require_auth": "yes",
        })))
    for destination, text_registry in registries:
        atomic_write(destination, text_registry)
    atomic_write(target, text)


if __name__ == "__main__":
    plan = json.loads(Path(sys.argv[4]).read_text())
    credentials = Path(os.environ["CREDENTIALS_DIRECTORY"])
    render(
        Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]),
        plan["networkCount"],
        [(credentials / entry["credential"], Path(entry["target"])) for entry in plan["sasl"]],
    )
