#!/usr/bin/env python3
"""Three-host, three-switch BMv2/Mininet lab for this repository."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shlex
import socket
import subprocess
import sys
import time
from typing import Iterable

from mininet.cli import CLI
from mininet.log import info, setLogLevel
from mininet.net import Mininet
from mininet.node import Switch
from mininet.topo import Topo


REPO_ROOT = Path(__file__).resolve().parents[1]
BMV2_JSON = REPO_ROOT / "build" / "switch.json"
CONTROL_PLANE_DIR = REPO_ROOT / "control-plane" / "mininet"
ARTIFACT_DIR = REPO_ROOT / "artifacts" / "mininet"

SWITCHES = {
    "s1": {"device_id": 1, "thrift_port": 9091},
    "s2": {"device_id": 2, "thrift_port": 9092},
    "s3": {"device_id": 3, "thrift_port": 9093},
}

HOSTS = {
    "h1": {
        "ip": "10.0.1.1/24",
        "mac": "00:00:00:00:01:01",
        "gateway_ip": "10.0.1.254",
        "gateway_mac": "00:aa:00:00:01:01",
    },
    "h2": {
        "ip": "10.0.2.2/24",
        "mac": "00:00:00:00:02:02",
        "gateway_ip": "10.0.2.254",
        "gateway_mac": "00:aa:00:00:02:01",
    },
    "h3": {
        "ip": "10.0.3.3/24",
        "mac": "00:00:00:00:03:03",
        "gateway_ip": "10.0.3.254",
        "gateway_mac": "00:aa:00:00:03:01",
    },
}


def wait_for_tcp_port(port: int, timeout: float = 5.0) -> None:
    """Wait until a local TCP listener is ready."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    raise RuntimeError(f"Thrift port {port} did not become ready")


class BMv2Switch(Switch):
    """Mininet switch backed by BMv2 simple_switch."""

    def __init__(
        self,
        name: str,
        json_path: str,
        thrift_port: int,
        device_id: int,
        **params: object,
    ) -> None:
        super().__init__(name, **params)
        self.json_path = Path(json_path)
        self.thrift_port = int(thrift_port)
        self.device_id = int(device_id)
        self.bmv2_pid: int | None = None

    def start(self, controllers: Iterable[object]) -> None:
        del controllers
        log_dir = ARTIFACT_DIR / "logs"
        pcap_dir = ARTIFACT_DIR / "pcaps"
        log_dir.mkdir(parents=True, exist_ok=True)
        pcap_dir.mkdir(parents=True, exist_ok=True)

        interface_args: list[str] = []
        for port, intf in sorted(self.intfs.items()):
            if not intf or intf.name == "lo":
                continue
            self.cmd(f"ip link set dev {shlex.quote(intf.name)} up")
            interface_args.extend(["--interface", f"{port}@{intf.name}"])

        command = [
            "simple_switch",
            "--device-id",
            str(self.device_id),
            "--thrift-port",
            str(self.thrift_port),
            "--log-console",
            "--pcap",
            str(pcap_dir),
            *interface_args,
            str(self.json_path),
            "--",
            "--priority-queues",
            "8",
        ]
        quoted_command = " ".join(shlex.quote(part) for part in command)
        log_path = log_dir / f"{self.name}.log"
        pid_text = self.cmd(
            f"{quoted_command} > {shlex.quote(str(log_path))} 2>&1 & echo $!"
        ).strip()
        try:
            self.bmv2_pid = int(pid_text.splitlines()[-1])
            wait_for_tcp_port(self.thrift_port)
        except Exception:
            log_text = log_path.read_text(errors="replace") if log_path.exists() else ""
            raise RuntimeError(
                f"{self.name} failed to start. BMv2 log:\n{log_text}"
            ) from None
        info(f"*** {self.name}: BMv2 ready on Thrift {self.thrift_port}\n")

    def stop(self, deleteIntfs: bool = True) -> None:  # noqa: N803 (Mininet API)
        if self.bmv2_pid is not None:
            self.cmd(f"kill {self.bmv2_pid} 2>/dev/null || true")
            time.sleep(0.1)
            self.cmd(f"kill -9 {self.bmv2_pid} 2>/dev/null || true")
            self.bmv2_pid = None
        super().stop(deleteIntfs=deleteIntfs)


class ThreeSwitchTopo(Topo):
    """h1--s1--s2--s3--h3, with h2 attached to s2."""

    def build(self) -> None:
        hosts = {
            name: self.addHost(name, ip=data["ip"], mac=data["mac"])
            for name, data in HOSTS.items()
        }
        switches = {
            name: self.addSwitch(
                name,
                cls=BMv2Switch,
                json_path=str(BMV2_JSON),
                thrift_port=data["thrift_port"],
                device_id=data["device_id"],
            )
            for name, data in SWITCHES.items()
        }

        self.addLink(hosts["h1"], switches["s1"], port1=0, port2=1)
        self.addLink(hosts["h2"], switches["s2"], port1=0, port2=1)
        self.addLink(hosts["h3"], switches["s3"], port1=0, port2=1)
        self.addLink(switches["s1"], switches["s2"], port1=2, port2=2)
        self.addLink(switches["s2"], switches["s3"], port1=3, port2=2)


def configure_hosts(net: Mininet) -> None:
    """Install deterministic host routes and static gateway neighbors."""
    for name, data in HOSTS.items():
        host = net.get(name)
        intf = host.defaultIntf().name
        host.cmd(f"ip link set dev {shlex.quote(intf)} address {data['mac']}")
        host.cmd(f"ip addr flush dev {shlex.quote(intf)}")
        host.cmd(f"ip addr add {data['ip']} dev {shlex.quote(intf)}")
        host.cmd(
            "ip neigh replace "
            f"{data['gateway_ip']} lladdr {data['gateway_mac']} "
            f"nud permanent dev {shlex.quote(intf)}"
        )
        host.cmd(
            f"ip route replace default via {data['gateway_ip']} "
            f"dev {shlex.quote(intf)}"
        )
        host.cmd(
            f"ethtool -K {shlex.quote(intf)} tx off rx off sg off tso off "
            "gso off gro off 2>/dev/null || true"
        )
        host.cmd("sysctl -qw net.ipv6.conf.all.disable_ipv6=1")
        info(
            f"*** {name}: {data['ip']} via {data['gateway_ip']} "
            f"({data['gateway_mac']})\n"
        )


def load_control_plane() -> None:
    """Load the per-switch BMv2 CLI command files."""
    log_dir = ARTIFACT_DIR / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    for switch_name, data in SWITCHES.items():
        command_file = CONTROL_PLANE_DIR / f"{switch_name}-commands.txt"
        command_lines = []
        for line in command_file.read_text().splitlines():
            stripped = line.strip()
            if stripped and not stripped.startswith("#"):
                command_lines.append(stripped)
        command_text = "\n".join(command_lines) + "\n"
        result = subprocess.run(
            ["simple_switch_CLI", "--thrift-port", str(data["thrift_port"])],
            input=command_text,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        output = result.stdout
        (log_dir / f"{switch_name}-cli.log").write_text(output)
        error_markers = (
            "Invalid table",
            "Invalid action",
            "Invalid table operation",
            "Unknown syntax",
            "Error:",
            "Traceback",
        )
        if result.returncode != 0 or any(marker in output for marker in error_markers):
            raise RuntimeError(
                f"Failed to configure {switch_name}. CLI output:\n{output}"
            )
        info(f"*** {switch_name}: control-plane entries installed\n")


def run_udp_probe(net: Mininet) -> bool:
    """Send an EF-marked UDP payload from h1 across all three switches to h3."""
    h1, h3 = net.get("h1", "h3")
    payload = "P4-FLOW-DEMO!!"
    output_path = Path("/tmp/p4-lab-udp-received.bin")
    output_path.unlink(missing_ok=True)
    server_process = h3.popen(
        [
            "/usr/bin/python3",
            "/workspace/mininet/udp_probe.py",
            "receive",
            "--bind",
            "10.0.3.3",
            "--port",
            "5000",
            "--output",
            str(output_path),
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    time.sleep(0.25)
    client_process = h1.popen(
        [
            "/usr/bin/python3",
            "/workspace/mininet/udp_probe.py",
            "send",
            "--destination",
            "10.0.3.3",
            "--port",
            "5000",
            "--tos",
            "0xb8",
            "--message",
            payload,
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    client_output, _ = client_process.communicate(timeout=3)
    server_output, _ = server_process.communicate(timeout=6)
    received = output_path.read_text() if output_path.exists() else ""
    info(f"*** UDP client: {client_output.strip()}\n")
    info(f"*** UDP server: {server_output.strip()}\n")
    return received == payload


def write_summary(ping_loss: float, udp_ok: bool) -> None:
    summary = {
        "topology": "h1--s1--s2--s3--h3 with h2 attached to s2",
        "ping_loss_percent": ping_loss,
        "udp_probe": "pass" if udp_ok else "fail",
        "result": "pass" if ping_loss == 0.0 and udp_ok else "fail",
    }
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    (ARTIFACT_DIR / "test-summary.json").write_text(
        json.dumps(summary, indent=2) + "\n"
    )


def restore_artifact_ownership() -> None:
    """Return bind-mounted artifacts to the host user after a container run."""
    uid_text = os.environ.get("LAB_HOST_UID")
    gid_text = os.environ.get("LAB_HOST_GID")
    if not uid_text or not gid_text or not ARTIFACT_DIR.parent.exists():
        return
    uid, gid = int(uid_text), int(gid_text)
    for path in [ARTIFACT_DIR.parent, *ARTIFACT_DIR.parent.rglob("*")]:
        os.chown(path, uid, gid)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--test", action="store_true", help="run ping and UDP tests")
    mode.add_argument("--cli", action="store_true", help="open the Mininet CLI")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    setLogLevel("info")
    if not BMV2_JSON.is_file():
        raise FileNotFoundError(f"Missing {BMV2_JSON}; run 'make compile' first")

    net: Mininet | None = None
    result = 1
    try:
        net = Mininet(topo=ThreeSwitchTopo(), controller=None, build=True)
        net.start()
        configure_hosts(net)
        load_control_plane()

        if args.cli:
            info("*** Entering Mininet CLI. Try: pingall\n")
            CLI(net)
            result = 0
        else:
            info("*** Running all-host ICMP test\n")
            ping_loss = float(net.pingAll(timeout="2"))
            info("*** Running h1 -> h3 UDP test\n")
            udp_ok = run_udp_probe(net)
            write_summary(ping_loss, udp_ok)
            result = 0 if ping_loss == 0.0 and udp_ok else 1
            info(
                f"*** RESULT: ping loss={ping_loss:.1f}%, "
                f"UDP={'PASS' if udp_ok else 'FAIL'}\n"
            )
    finally:
        if net is not None:
            net.stop()
        restore_artifact_ownership()
    return result


if __name__ == "__main__":
    sys.exit(main())
