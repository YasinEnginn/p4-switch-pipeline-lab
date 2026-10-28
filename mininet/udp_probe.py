#!/usr/bin/env python3
"""Small UDP sender/receiver used by the automated Mininet test."""

from __future__ import annotations

import argparse
from pathlib import Path
import socket


def parse_int(value: str) -> int:
    return int(value, 0)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="operation", required=True)

    sender = subparsers.add_parser("send")
    sender.add_argument("--destination", required=True)
    sender.add_argument("--port", required=True, type=int)
    sender.add_argument("--tos", type=parse_int, default=0)
    sender.add_argument("--message", required=True)

    receiver = subparsers.add_parser("receive")
    receiver.add_argument("--bind", required=True)
    receiver.add_argument("--port", required=True, type=int)
    receiver.add_argument("--output", required=True, type=Path)
    receiver.add_argument("--timeout", type=float, default=5.0)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        if args.operation == "send":
            sock.setsockopt(socket.IPPROTO_IP, socket.IP_TOS, args.tos)
            payload = args.message.encode()
            sock.sendto(payload, (args.destination, args.port))
            print(f"sent {len(payload)} bytes to {args.destination}:{args.port}")
            return

        sock.settimeout(args.timeout)
        sock.bind((args.bind, args.port))
        payload, peer = sock.recvfrom(2048)
        args.output.write_bytes(payload)
        print(f"received {len(payload)} bytes from {peer[0]}:{peer[1]}")


if __name__ == "__main__":
    main()
