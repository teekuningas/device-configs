#!/usr/bin/env python3
"""Rehearse ZNC with synthetic IRC traffic on an isolated host Podman network."""

import hashlib
import json
import secrets
import subprocess
import time
import uuid


IMAGES = {
    "znc": "docker.io/library/znc@sha256:5feabfc6dbf5504d3620cd9142e5bd85b338dc7605c4e0bc5c9025e3eab8c9f0",
    "ergo": "ghcr.io/ergochat/ergo@sha256:d96402341db6edd6302bde1a8a418a90abc7bfc99ee08599ee477fc51cb1ce71",
    "python": "docker.io/library/python@sha256:608322fe51a9b889eee5ed6015c854e77dc44d00c116435f56b69bf6f14c88f4",
}
RESTRICTIONS = [
    "--read-only",
    "--cap-drop=ALL",
    "--security-opt=no-new-privileges",
    "--memory=256m",
    "--pids-limit=128",
    "--tmpfs=/tmp:rw,nosuid,nodev,size=16m,mode=1777",
]

CLIENT_TESTS = r'''
import datetime
import json
import socket
import ssl
import time


class Client:
    def __init__(self, host, nick, network=None, identifier=None):
        raw = socket.create_connection((host, 6697 if network else 6667), timeout=5)
        if network:
            context = ssl.create_default_context(cadata=settings["certificate"])
            self.socket = context.wrap_socket(raw, server_hostname="znc.test")
        else:
            self.socket = raw
        self.socket.settimeout(0.2)
        self.pending = b""
        self.lines = []
        self.send("CAP LS 302")
        self.until(lambda line: " CAP " in line and " LS " in line)
        self.send("CAP REQ :server-time")
        self.until(lambda line: " CAP " in line and " ACK " in line)
        if network:
            self.send("PASS rehearsal@" + (identifier or nick) + "/" + network + ":" + settings["password"])
        self.send("NICK " + nick)
        self.send("USER probe 0 * :Synthetic rehearsal client")
        self.send("CAP END")
        self.until(lambda line: " 001 " in line)
        self.barrier()

    def send(self, line):
        self.socket.sendall((line + "\r\n").encode())

    def until(self, predicate, timeout=10):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if b"\n" not in self.pending:
                try:
                    data = self.socket.recv(65536)
                except socket.timeout:
                    continue
                if not data:
                    raise RuntimeError("IRC connection closed unexpectedly")
                self.pending += data
                continue
            raw, self.pending = self.pending.split(b"\n", 1)
            line = raw.rstrip(b"\r").decode()
            self.lines.append(line)
            if line.startswith("PING "):
                self.send("PONG " + line[5:])
            if predicate(line):
                return line
        raise TimeoutError("Expected IRC response not received; synthetic transcript: " + repr(self.lines[-12:]))

    def barrier(self):
        self.send("PING :rehearsal-barrier")
        self.until(lambda line: " PONG " in line and "rehearsal-barrier" in line)

    def join(self, channel):
        self.send("JOIN " + channel)
        self.until(lambda line: " 366 " in line and channel in line)

    def close(self):
        self.send("QUIT :rehearsal phase complete")
        self.socket.close()


def original_time(line):
    assert line.startswith("@"), "Original timestamp tag missing"
    tags = dict(item.split("=", 1) for item in line.split(" ", 1)[0][1:].split(";") if "=" in item)
    value = tags["time"]
    datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
    return value


def wait_upstream(sender, nick):
    for attempt in range(50):
        start = len(sender.lines)
        sender.send("WHOIS " + nick)
        sender.until(lambda line: " 318 " in line and nick in line)
        found = [line for line in sender.lines[start:] if " 311 " in line and nick in line]
        if found:
            return found[0]
        time.sleep(0.2)
    raise RuntimeError("Bouncer did not connect to private upstream")


def check_history(client, expected=None):
    channel = [line for line in client.lines if " PRIVMSG #alpha :bounded-" in line]
    markers = [line.split(" PRIVMSG #alpha :", 1)[1] for line in channel]
    assert markers == ["bounded-" + str(i) for i in range(3, 8)], markers
    queries = [line for line in client.lines if " PRIVMSG bouncera :private-offline" in line]
    assert len(queries) == 1, queries
    result = {line.split(" PRIVMSG ", 1)[1]: original_time(line) for line in channel + queries}
    if expected is not None:
        assert result == expected, "Original timestamps or replay contents changed"
    return result


sender = Client("irc.test", "sender")
whois = wait_upstream(sender, "bouncera")
wait_upstream(sender, "bouncerb")
sender.join("#alpha")
sender.join("#beta")

if settings["phase"] == "initial":
    first = Client("znc.test", "bouncera", "alpha", "desktop")
    second = Client("znc.test", "bouncera", "alpha", "mobile")
    beta = Client("znc.test", "bouncerb", "beta")
    sender.send("PRIVMSG #alpha :live-two-clients")
    one = first.until(lambda line: " PRIVMSG #alpha :live-two-clients" in line)
    two = second.until(lambda line: " PRIVMSG #alpha :live-two-clients" in line)
    assert original_time(one) == original_time(two)
    sender.send("PRIVMSG #beta :network-beta-only")
    beta.until(lambda line: " PRIVMSG #beta :network-beta-only" in line)
    first.barrier()
    assert not any("network-beta-only" in line for line in first.lines)
    assert not any("live-two-clients" in line for line in beta.lines)
    first.close()
    second.close()
    beta.close()
    wait_upstream(sender, "bouncera")
    wait_upstream(sender, "bouncerb")
    for index in range(8):
        sender.send("PRIVMSG #alpha :bounded-" + str(index))
    sender.send("PRIVMSG bouncera :private-offline")
    sender.barrier()
    first = Client("znc.test", "bouncera", "alpha", "desktop")
    expected = check_history(first)
    second = Client("znc.test", "bouncera", "alpha", "mobile")
    check_history(second, expected)
    first.close()
    second.close()
    print(json.dumps({"checks": [
        "two clients receive the same live message and original timestamp",
        "two upstream connections selected through one ZNC listener",
        "network message isolation",
        "upstream presence survives all client disconnects",
        "bounded five-line channel backlog",
        "offline private-message backlog",
        "one client does not clear another client's backlog",
    ], "expected": expected}))
else:
    assert ":Rehearsal " + settings["realname"] in whois, whois
    client = Client("znc.test", "bouncera", "alpha")
    check_history(client, settings["expected"])
    client.close()
    print(json.dumps({"checks": [
        settings["phase"] + ": channel and private backlog survives with original timestamps",
        settings["phase"] + ": configured upstream real name applied",
    ]}))
sender.close()
'''


def podman(*arguments, data=None, timeout=60):
    result = subprocess.run(
        ["podman", *arguments],
        input=data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )
    if result.returncode:
        raise RuntimeError(
            "Podman " + arguments[0] + " failed: " + result.stderr.decode(errors="replace")
        )
    return result.stdout + result.stderr if arguments[0] == "logs" else result.stdout


def main():
    for image in IMAGES.values():
        podman("image", "exists", image)
    prefix = "irc-rehearsal-" + uuid.uuid4().hex[:12]
    network = prefix + "-net"
    znc = prefix + "-znc"
    ergo = prefix + "-ergo"
    volume = prefix + "-state"
    restored_volume = prefix + "-restored"
    containers = []
    volumes = []
    network_created = False
    checks = []
    password = secrets.token_hex(24)
    save_key = secrets.token_hex(24)
    password_hash = hashlib.sha256(password.encode()).hexdigest()

    def volume_command(name, script=None, archive=None, readonly=False):
        arguments = [
            "run", "--rm", "-i", "--network=none", "--user=100:65533",
            *RESTRICTIONS, "--volume=" + name + ":/znc-data:" + ("ro" if readonly else "U"),
        ]
        if archive is not None:
            return podman(
                *arguments, "--entrypoint=/bin/tar", IMAGES["znc"],
                "-C", "/znc-data", "-xf", "-", data=archive,
            )
        return podman(
            *arguments, "--entrypoint=/bin/sh", IMAGES["znc"], "-s",
            data=script.encode(),
        )

    def start_znc(state):
        podman(
            "run", "-d", "--name=" + znc, "--network=" + network,
            "--network-alias=znc.test", "--user=100:65533", *RESTRICTIONS,
            "--volume=" + state + ":/znc-data:U", IMAGES["znc"],
        )
        containers.append(znc)

    def remove_znc():
        podman("stop", "--time=10", znc)
        podman("rm", znc)
        containers.remove(znc)

    def clients(phase, certificate, expected=None, realname="v1"):
        settings = {
            "phase": phase, "certificate": certificate, "password": password,
            "expected": expected, "realname": realname,
        }
        source = "settings = " + repr(settings) + "\n" + CLIENT_TESTS
        name = prefix + "-clients"
        containers.append(name)
        try:
            result = podman(
                "run", "--rm", "-i", "--name=" + name, "--network=" + network,
                "--user=65534:65534", *RESTRICTIONS, "--entrypoint=python3",
                IMAGES["python"], "-u", "-", data=source.encode(), timeout=90,
            )
        finally:
            exists = subprocess.run(
                ["podman", "container", "exists", name],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            if exists.returncode == 0:
                podman("rm", "--force", name)
            containers.remove(name)
        report = json.loads(result)
        checks.extend(report["checks"])
        print("PASS:", phase, flush=True)
        return report.get("expected")

    try:
        podman("network", "create", "--internal", "--label=irc-rehearsal=" + prefix, network)
        network_created = True
        for name in (volume, restored_volume):
            podman("volume", "create", "--label=irc-rehearsal=" + prefix, name)
            volumes.append(name)
        ergo_script = r'''
set -eu
umask 077
awk '
    /^history:/ { history = 1 }
    history && /^    enabled:/ { sub(/true/, "false"); history = 0 }
    {
        gsub(/path: languages/, "path: /ircd-bin/languages")
        gsub(/motd: ergo.motd/, "motd: rehearsal.motd")
        print
    }
' /ircd-bin/default.yaml > /ircd/ircd.yaml
printf 'Private synthetic rehearsal only\n' > /ircd/rehearsal.motd
exec /ircd-bin/run.sh
'''
        podman(
            "run", "-d", "--name=" + ergo, "--network=" + network,
            "--network-alias=irc.test", "--user=65534:65534", *RESTRICTIONS,
            "--tmpfs=/ircd:rw,nosuid,nodev,size=32m,mode=1777",
            "--entrypoint=/bin/sh", IMAGES["ergo"], "-c", ergo_script,
        )
        containers.append(ergo)
        configuration = f"""Version = 1.10.3
MaxBufferSize = 5
ConnectDelay = 0
ServerThrottle = 1
SSLCertFile = /znc-data/cert.pem
SSLKeyFile = /znc-data/key.pem
<Listener private>
    Port = 6697
    IPv4 = true
    IPv6 = false
    SSL = true
    AllowIRC = true
    AllowWeb = false
</Listener>
<User rehearsal>
    Nick = bouncera
    Ident = rehearsal
    RealName = Rehearsal v1
    MultiClients = true
    AutoClearChanBuffer = false
    AutoClearQueryBuffer = false
    ChanBufferSize = 5
    QueryBufferSize = 5
    <Pass password>
        Method = sha256
        Hash = {password_hash}
    </Pass>
    <Network alpha>
        Server = irc.test 6667
        LoadModule = savebuff {save_key}
        <Chan #alpha>
        </Chan>
    </Network>
    <Network beta>
        Nick = bouncerb
        Server = irc.test 6667
        LoadModule = savebuff {save_key}
        <Chan #beta>
        </Chan>
    </Network>
</User>
"""
        volume_command(volume, """set -eu
umask 077
mkdir /znc-data/configs
openssl req -x509 -newkey rsa:2048 -noenc -days 1 -subj /CN=znc.test -addext subjectAltName=DNS:znc.test -keyout /znc-data/key.pem -out /znc-data/cert.pem >/tmp/keygen.out 2>&1
cat > /znc-data/configs/znc.conf <<'CONFIG'
""" + configuration + "CONFIG\n")
        certificate = volume_command(volume, "cat /znc-data/cert.pem", readonly=True).decode()
        start_znc(volume)
        for name in (ergo, znc):
            info = json.loads(podman("inspect", name))[0]
            if not info["State"]["Running"]:
                raise RuntimeError(name + " failed to start:\n" + podman("logs", name).decode())
            assert not info["HostConfig"]["PortBindings"], "Unexpected published port"
        assert json.loads(podman("network", "inspect", network))[0]["internal"]
        history_setting = podman(
            "exec", ergo, "sh", "-c",
            "awk '/^history:/ { h=1; next } h && /^    enabled:/ { print $2; exit }' /ircd/ircd.yaml",
        ).decode().strip()
        assert history_setting == "false", "Disable upstream history to avoid false-positive persistence tests"
        checks.append("internal network, no published ports, non-root services, upstream history disabled")
        expected = clients("initial", certificate)
        podman("restart", "--time=10", znc)
        clients("restart", certificate, expected)
        remove_znc()
        archive = podman(
            "run", "--rm", "--network=none", "--user=100:65533", *RESTRICTIONS,
            "--volume=" + volume + ":/znc-data:ro", "--entrypoint=/bin/tar",
            IMAGES["znc"], "-C", "/znc-data", "-cf", "-", ".",
        )
        assert archive, "Empty state backup"
        volume_command(restored_volume, archive=archive)
        volume_command(
            volume,
            "set -eu; sed -i 's/RealName = Rehearsal v1/RealName = Rehearsal v2/' /znc-data/configs/znc.conf",
        )
        start_znc(volume)
        clients("recreation", certificate, expected, realname="v2")
        remove_znc()
        start_znc(restored_volume)
        clients("restored-backup", certificate, expected)
        print(json.dumps({
            "images": IMAGES,
            "checks": checks,
            "state_backup_bytes": len(archive),
            "state_backup_sha256": hashlib.sha256(archive).hexdigest(),
            "limitations": [
                "No production IRC networks, data, credentials or conversations used",
                "Two ZNC network definitions use separate nicks on one private Ergo server",
                "Upstream plaintext is confined to the internal synthetic test network",
                "Test certificate is self-signed and trusted only by the test clients",
                "Tailnet exposure, certificate renewal and ident are not tested",
                "Retained buffers replay again on reconnect; per-device unread synchronization is not implemented",
                "Configuration update tested only while stopped; declarative secret provisioning remains undecided",
                "Graceful restart tested; crash/power-loss durability is not established",
            ],
        }, indent=2), flush=True)
    finally:
        for name in reversed(containers):
            podman("rm", "--force", name)
        for name in reversed(volumes):
            podman("volume", "rm", name)
        if network_created:
            podman("network", "rm", network)
        print("Rehearsal containers, volumes and network removed.", flush=True)


if __name__ == "__main__":
    main()
