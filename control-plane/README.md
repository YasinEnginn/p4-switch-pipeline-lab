# Control-plane examples

The P4 program defines table schemas and actions. Runtime software supplies the
entries that make those tables useful.

`bmv2-cli.txt` is a small BMv2 Thrift CLI example for a three-port lab switch.
Review and adjust every port and MAC address before using it. Compile the P4
program first, start `simple_switch` with the resulting JSON, and then run:

```bash
simple_switch_CLI < control-plane/bmv2-cli.txt
```

## Example policy encoded by the file

- Drop TCP traffic from `10.0.0.0/24` to `10.0.0.99`.
- Classify DiffServ EF (`0xb8`, ignoring ECN bits) into priority 5.
- Route `10.0.1.0/24` directly through port 1.
- Route `10.0.2.0/24` through ECMP group 1 with two members on ports 2 and 3.
- Forward one known destination MAC through port 1.
- Select multicast group 100 for Ethernet broadcast.
- Map internal priority 5 to VLAN PCP 5.

## Multicast requires a second configuration step

The `multicast` P4 action only writes a group ID. BMv2's packet-replication
engine must also know the group's replica ports. In an interactive
`simple_switch_CLI` session, create a group and node, note the returned node
handle, and associate them:

```text
mc_mgrp_create 100
mc_node_create 0 1 2 3
mc_node_associate 100 <node-handle-returned-above>
```

The dynamic handle is why these commands are not embedded in the batch file.

## P4Runtime

For a P4Runtime deployment, use `simple_switch_grpc`, install both
`build/switch.json` and `build/switch.p4info.txtpb` with
`SetForwardingPipelineConfig`, then write entries using the generated P4Info
names and IDs. Numeric IDs are compiler-generated; applications should resolve
them from P4Info instead of hard-coding the values in a particular build.

The text file in this directory uses BMv2's target-specific Thrift CLI because
it is compact and easy to read. P4Runtime is the portable control-plane API.
