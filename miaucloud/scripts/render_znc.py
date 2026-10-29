#!/usr/bin/env python3
"""Install Nix-owned ZNC structure with private runtime credentials."""

import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile


def render(template, secret_file, target, uid, gid):
    metadata = secret_file.stat()
    if metadata.st_uid != os.geteuid() or stat.S_IMODE(metadata.st_mode) != 0o600:
        raise ValueError("ZNC secrets must belong to the renderer user and have mode 0600")
    secrets = json.loads(secret_file.read_text())
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
    if text.count("@PASSWORD_HASH@") != 1 or text.count("@SAVEBUFF_KEY@") != 3:
        raise ValueError("Unexpected ZNC credential placeholders")
    text = text.replace("@PASSWORD_HASH@", password_hash).replace("@SAVEBUFF_KEY@", savebuff_key)
    fd, temporary = tempfile.mkstemp(prefix=".znc.conf-", dir=target.parent)
    try:
        with os.fdopen(fd, "w") as output:
            output.write(text)
            output.flush()
            os.fchmod(output.fileno(), 0o600)
            os.fchown(output.fileno(), uid, gid)
            os.fsync(output.fileno())
        os.replace(temporary, target)
    finally:
        Path(temporary).unlink(missing_ok=True)


if __name__ == "__main__":
    render(
        Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]),
        int(sys.argv[4]), int(sys.argv[5]),
    )
