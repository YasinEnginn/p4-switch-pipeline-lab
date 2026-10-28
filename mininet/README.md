# Three-switch Mininet lab

This lab runs the repository's compiled P4 pipeline on three BMv2
`simple_switch` instances. Each host lives in a separate IPv4 subnet, so every
successful host-to-host packet exercises L3 forwarding instead of relying on a
shared L2 broadcast domain.

## Topology

```text
10.0.1.1/24                                               10.0.3.3/24
     h1                                                       h3
      |                                                        |
   (1)|                                                        |(1)
     s1 (2)----------------(2) s2 (3)----------------(2) s3
                                |(1)
                                |
                               h2
                          10.0.2.2/24

Logical path from h1 to h3: h1 -> s1 -> s2 -> s3 -> h3
```

The exact switch port map is:

| Switch | Port | Connected node |
|---|---:|---|
| `s1` | 1 | `h1` |
| `s1` | 2 | `s2` port 2 |
| `s2` | 1 | `h2` |
| `s2` | 2 | `s1` port 2 |
| `s2` | 3 | `s3` port 2 |
| `s3` | 1 | `h3` |
| `s3` | 2 | `s2` port 3 |

## Addressing

| Host | Address | MAC | Static gateway neighbor |
|---|---|---|---|
| `h1` | `10.0.1.1/24` | `00:00:00:00:01:01` | `10.0.1.254` -> `00:aa:00:00:01:01` |
| `h2` | `10.0.2.2/24` | `00:00:00:00:02:02` | `10.0.2.254` -> `00:aa:00:00:02:01` |
| `h3` | `10.0.3.3/24` | `00:00:00:00:03:03` | `10.0.3.254` -> `00:aa:00:00:03:01` |

The gateway IPs do not belong to Linux router processes. They are deterministic
next-hop identities whose MAC addresses deliver packets to the local P4 switch.
Static neighbor entries keep this first routing lab focused on IPv4 processing
instead of ARP control-plane behavior.

## Automated test

From the repository root:

```bash
make mininet-test
```

The command builds a self-contained image from the official `p4lang/p4c` image,
installs Mininet, compiles the P4 program, starts all three switches, loads the
three control-plane files, and runs:

1. `pingall` between all three hosts.
2. An EF-marked (`IP_TOS=0xb8`) UDP packet carrying `P4-FLOW-DEMO!!` from `h1`
   to `h3` across all three switches.

A passing run ends with:

```text
*** RESULT: ping loss=0.0%, UDP=PASS
```

Docker must be available. The lab container requires `--privileged` because
Mininet creates network namespaces and virtual Ethernet interfaces. It is
isolated inside the disposable container; host Mininet cleanup is not used.

## Interactive mode

```bash
make mininet-cli
```

Useful commands at the Mininet prompt:

```text
mininet> net
mininet> dump
mininet> pingall
mininet> h1 ping -c 2 10.0.3.3
mininet> h1 ip route
mininet> h2 ip neigh
mininet> exit
```

## Control plane and artifacts

Per-switch rules live in:

```text
control-plane/mininet/s1-commands.txt
control-plane/mininet/s2-commands.txt
control-plane/mininet/s3-commands.txt
```

Each switch gets three LPM routes and a QoS entry for DSCP EF. Runtime output is
written under `artifacts/mininet/`:

```text
artifacts/mininet/
├── test-summary.json
├── logs/
│   ├── s1.log
│   ├── s1-cli.log
│   └── ...
└── pcaps/
    └── per-interface packet captures
```

The runner restores artifact ownership to the invoking host user before the
container exits.

## Native execution

The Docker wrapper is the supported reproducible path. If `p4c`, BMv2,
`simple_switch_CLI`, Mininet, `ip`, `ping`, and `ethtool` are all installed
natively, the equivalent command is:

```bash
make test
sudo python3 mininet/lab.py --test
```
