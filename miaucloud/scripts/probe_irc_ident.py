#!/usr/bin/env python3
"""Probe oidentd with synthetic local sockets; never contact an IRC network."""

import json
import os
from pathlib import Path
import pwd
import shutil
import socket
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
HOST_UID = BASE + 100


def run(*arguments):
    return subprocess.run(
        arguments, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        check=True, timeout=60,
    ).stdout


def listener(address):
    server = socket.socket()
    server.settimeout(15)
    server.bind((address, 0))
    server.listen(4)
    return server


def ident(address, port, client_port, server_port):
    with socket.create_connection(
        (address, port), timeout=5, source_address=(address, 0),
    ) as query:
        query.sendall(f"{client_port}, {server_port}\r\n".encode())
        response = b""
        while b"\n" not in response:
            part = query.recv(512)
            if not part:
                raise RuntimeError("Ident daemon closed without a complete response")
            response += part
            if len(response) > 1024:
                raise RuntimeError("Oversized ident response")
    fields = [part.strip() for part in response.decode("ascii").strip().split(":")]
    pair = [int(value.strip()) for value in fields[0].split(",")]
    if pair != [client_port, server_port]:
        raise RuntimeError("Ident response identified the wrong port pair")
    if fields[1] == "USERID" and len(fields) == 4:
        return {"type": fields[1], "value": fields[3]}
    if fields[1] == "ERROR" and len(fields) == 3:
        return {"type": fields[1], "value": fields[2]}
    raise RuntimeError("Unexpected ident response: " + repr(fields))


def main():
    if os.geteuid() != 0:
        raise RuntimeError("Run as root on miaucloud")
    run("podman", "image", "exists", IMAGE)
    containers = run("podman", "ps", "--all", "--quiet").decode().split()
    if containers:
        for info in json.loads(run("podman", "inspect", *containers)):
            mappings = info["HostConfig"].get("IDMappings") or {}
            for kind in ("UidMap", "GidMap"):
                for mapping in mappings.get(kind) or []:
                    _, start, size = map(int, mapping.split(":"))
                    if start < BASE + 65536 and BASE < start + size:
                        raise RuntimeError("Test namespace range is already in use")
    account = pwd.getpwnam("zairex")
    named_account = pwd.getpwnam("nobody")
    unrelated_account = pwd.getpwnam("oidentd")
    if named_account.pw_uid == 0 or BASE <= named_account.pw_uid < BASE + 65536:
        raise RuntimeError("Need a separate unprivileged named account for the control")
    bridge = json.loads(run("podman", "network", "inspect", "podman"))[0]
    if bridge["network_interface"] != "podman0":
        raise RuntimeError("Expected the existing trusted podman0 bridge")
    gateway = bridge["subnets"][0]["gateway"]
    pid = int(run("systemctl", "show", "oidentd", "--property=MainPID", "--value"))
    executable = str(Path(f"/proc/{pid}/exe").resolve(strict=True))
    prefix = "irc-ident-probe-" + uuid.uuid4().hex[:12]
    root = Path(tempfile.mkdtemp(prefix=prefix + "-"))
    os.chmod(root, 0o755)
    names = []
    processes = []
    sockets = []
    report = {}

    def connect_container(network, server, host_uid=HOST_UID):
        name = prefix + "-" + str(len(names))
        names.append(name)
        address, port = server.getsockname()
        uid_options = [f"--uidmap=0:{BASE}:65536"]
        if host_uid != HOST_UID:
            uid_options = [
                f"--uidmap=0:{BASE}:100",
                f"--uidmap=100:{host_uid}:1",
                f"--uidmap=101:{BASE + 101}:65435",
            ]
        run(
            "podman", "run", "-d", "-i", "--name=" + name,
            "--network=" + network,
            *uid_options, f"--gidmap=0:{BASE}:65536",
            "--user=100:65533", "--read-only", "--cap-drop=ALL",
            "--security-opt=no-new-privileges", "--memory=32m", "--pids-limit=16",
            "--entrypoint=/usr/bin/nc", IMAGE, address, str(port),
        )
        connection, peer = server.accept()
        sockets.append(connection)
        info = json.loads(run("podman", "inspect", name))[0]
        if not info["State"]["Running"] or info["HostConfig"].get("PortBindings"):
            raise RuntimeError("Unexpected synthetic client state or published ports")
        if Path(f"/proc/{info['State']['Pid']}").stat().st_uid != host_uid:
            raise RuntimeError("Synthetic client has unexpected host UID")
        return peer[1]

    def connect_host(server, user=account):
        address, port = server.getsockname()
        client = subprocess.Popen(
            [sys.executable, "-c",
             "import socket,sys; s=socket.create_connection((sys.argv[1],int(sys.argv[2]))); "
             "s.settimeout(60); s.recv(1); s.close()", address, str(port)],
            user=user.pw_uid, group=user.pw_gid, extra_groups=(),
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
        )
        processes.append(client)
        connection, peer = server.accept()
        sockets.append(connection)
        return peer[1]

    try:
        host_server = listener("127.0.0.1")
        sockets.append(host_server)
        host_port = host_server.getsockname()[1]
        baseline_port = connect_host(host_server)
        report["existing_daemon_host_user"] = ident("127.0.0.1", 113, baseline_port, host_port)
        if report["existing_daemon_host_user"] != {"type": "USERID", "value": account.pw_name}:
            raise RuntimeError("Existing daemon did not identify the baseline host user")
        unrelated_port = connect_host(host_server, unrelated_account)
        report["existing_daemon_unrelated_host_user"] = ident(
            "127.0.0.1", 113, unrelated_port, host_port,
        )
        if report["existing_daemon_unrelated_host_user"] != {
            "type": "USERID", "value": unrelated_account.pw_name,
        }:
            raise RuntimeError("Existing daemon did not identify the unrelated control user")
        mapped_port = connect_container("host", host_server)
        report["existing_daemon_mapped_host_network"] = ident(
            "127.0.0.1", 113, mapped_port, host_port,
        )
        matching_uids = []
        for line in Path("/proc/net/tcp").read_text().splitlines()[1:]:
            fields = line.split()
            local = int(fields[1].split(":")[1], 16)
            remote = int(fields[2].split(":")[1], 16)
            if local == mapped_port and remote == host_port and fields[3] == "01":
                matching_uids.append(int(fields[7]))
        if matching_uids != [HOST_UID]:
            raise RuntimeError("Host cannot see the expected mapped synthetic socket UID")
        report["host_visible_socket_uid"] = matching_uids[0]
        try:
            pwd.getpwuid(HOST_UID)
        except KeyError:
            report["candidate_uid_has_host_account"] = False
        else:
            raise RuntimeError("Candidate UID already has a host account; review before probing")

        named_port = connect_container("host", host_server, named_account.pw_uid)
        report["existing_daemon_named_mapped_host_network"] = ident(
            "127.0.0.1", 113, named_port, host_port,
        )
        if report["existing_daemon_named_mapped_host_network"] != {
            "type": "USERID", "value": named_account.pw_name,
        }:
            raise RuntimeError("Daemon did not identify a mapped socket with a named host UID")

        bridge_server = listener(gateway)
        sockets.append(bridge_server)
        bridge_port = connect_container("podman", bridge_server)
        report["existing_daemon_mapped_bridge"] = ident(
            gateway, 113, bridge_port, bridge_server.getsockname()[1],
        )

        configuration = root / "oidentd.conf"
        configuration.write_text(
            f'user "{named_account.pw_name}" {{\n'
            f'    fport {host_port} {{ force reply "{account.pw_name}" }}\n'
            "}\n"
        )
        configuration.chmod(0o644)
        with listener("127.0.0.1") as reservation:
            private_port = reservation.getsockname()[1]
        with (root / "daemon.log").open("w+b") as log:
            daemon = subprocess.Popen(
                [executable, "-i", "-S", "-a", "127.0.0.1", "-p", str(private_port),
                 "-C", str(configuration), "-u", "oidentd", "-g", "nogroup"],
                stdin=subprocess.DEVNULL, stdout=log, stderr=log,
            )
            processes.append(daemon)
            for attempt in range(50):
                if daemon.poll() is not None:
                    log.seek(0)
                    raise RuntimeError("Private ident daemon failed: " + log.read().decode())
                try:
                    with socket.create_connection(("127.0.0.1", private_port), timeout=0.2):
                        break
                except ConnectionRefusedError:
                    if attempt == 49:
                        raise
                    time.sleep(0.1)
            report["scoped_daemon_mapped_host_network"] = ident(
                "127.0.0.1", private_port, named_port, host_port,
            )
            if report["scoped_daemon_mapped_host_network"] != {
                "type": "USERID", "value": account.pw_name,
            }:
                log.seek(0)
                raise RuntimeError(
                    "Scoped rule did not identify the mapped socket: "
                    + json.dumps(report) + "\n" + log.read().decode()
                )
            report["scoped_daemon_original_host_user"] = ident(
                "127.0.0.1", private_port, baseline_port, host_port,
            )
            if report["scoped_daemon_original_host_user"] != report["existing_daemon_host_user"]:
                raise RuntimeError("Scoped rule changed the host user's reply")
            report["scoped_daemon_unrelated_host_user"] = ident(
                "127.0.0.1", private_port, unrelated_port, host_port,
            )
            if report["scoped_daemon_unrelated_host_user"] != report[
                "existing_daemon_unrelated_host_user"
            ]:
                raise RuntimeError("Scoped rule leaked to an unrelated user")
            other_server = listener("127.0.0.1")
            sockets.append(other_server)
            other_port = connect_container("host", other_server, named_account.pw_uid)
            report["scoped_daemon_mapped_other_destination_port"] = ident(
                "127.0.0.1", private_port, other_port, other_server.getsockname()[1],
            )
            if report["scoped_daemon_mapped_other_destination_port"] != report[
                "existing_daemon_named_mapped_host_network"
            ]:
                raise RuntimeError("Scoped rule leaked to another destination port")
            with socket.socket() as unused:
                unused.bind(("127.0.0.1", 0))
                report["scoped_daemon_nonexistent_connection"] = ident(
                    "127.0.0.1", private_port, unused.getsockname()[1], host_port,
                )
            if report["scoped_daemon_nonexistent_connection"] != {"type": "ERROR", "value": "NO-USER"}:
                raise RuntimeError("Scoped rule answered for a nonexistent connection")
        current_pid = int(run("systemctl", "show", "oidentd", "--property=MainPID", "--value"))
        if current_pid != pid:
            raise RuntimeError("Production ident daemon PID changed during the probe")
        print(json.dumps({
            "results": report,
            "mapped_uid": HOST_UID,
            "named_control_account": named_account.pw_name,
            "limitations": [
                "Bridge-to-host test, not an external NAT/IRC admission test",
                "Only synthetic local TCP connections; no IRC messages or production configuration changes",
                "Scoped policy is tested in a separate loopback-only ident daemon, not deployed",
                "Named-account control uses a synthetic nc process, not ZNC or a production account change",
            ],
        }, indent=2), flush=True)
    finally:
        for name in reversed(names):
            exists = subprocess.run(
                ["podman", "container", "exists", name],
                stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=30,
            )
            if exists.returncode == 0:
                run("podman", "rm", "--force", name)
            elif exists.returncode != 1:
                raise RuntimeError("Could not check synthetic client cleanup")
        for connection in reversed(sockets):
            connection.close()
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=10)
        shutil.rmtree(root)
        print("Synthetic clients, private ident daemon and temporary state removed.", flush=True)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        print(error.stderr.decode(), file=sys.stderr)
        raise
