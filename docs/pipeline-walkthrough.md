# The complete packet journey through this P4 switch

This guide follows one packet in execution order. It separates what the P4
program defines from what the target and control plane provide, because that
boundary is the key to understanding a real P4 switch.

## 0. Before any packet arrives: compile and configure

P4 describes a programmable data plane; it does not, by itself, provide the
routes and policies that should be installed at runtime.

The compiler consumes `p4src/main.p4` and the `v1model` architecture definition.
It produces two important artifacts:

1. `switch.json` describes the executable BMv2 pipeline.
2. `switch.p4info.txtpb` describes the tables, match fields, actions,
   parameters, counters, and IDs visible to a P4Runtime control plane.

The switch loads the data-plane artifact. A controller or BMv2 CLI then inserts
entries such as "route `10.0.1.0/24` to port 1." The P4 source defines the shape
of that entry; the control plane supplies its operational values.

## 1. Arrival: the target creates packet and intrinsic context

BMv2 receives a frame on a physical or virtual interface. The target exposes
the frame as a `packet_in` object and initializes `standard_metadata_t`.

Important fields at this point include:

- `ingress_port`: where the packet arrived.
- `packet_length`: the received length in bytes.
- `parser_error`: the parser result, initially `NoError` for a new packet.
- `checksum_error`: later set when checksum verification fails.

These fields belong to the `v1model` architecture, not to Ethernet or IP. User
metadata in `metadata_t` is private scratch space carried between this
program's pipeline stages for the same packet.

## 2. Parse: turn bytes into typed, valid headers

`SwitchParser` begins in `start` and immediately enters `parse_ethernet`.
`packet.extract(hdr.ethernet)` removes the next 14 bytes from the parser input
and writes them into typed fields.

The parser then branches on EtherType:

```text
Ethernet
├── 0x8100 -> one VLAN tag -> inner EtherType
├── 0x0806 -> ARP
├── 0x0800 -> IPv4 -> TCP, UDP, ICMP, or another IP protocol
└── other  -> accept with only Ethernet valid
```

Extraction does two things: it copies bits and marks that header instance as
valid. Validity matters throughout the program. A later `packet.emit` outputs
only valid headers, and controls can use `hdr.ipv4.isValid()` to select logic.

For IPv4, the parser verifies that `version == 4` and deliberately requires
`IHL == 5`. A failure enters the parser's `reject` state and records a custom
error in `standard_metadata.parser_error`. Rejecting options is a design choice
for this lab, not a limitation of P4.

The transport parsers extract only fixed headers. The remaining payload stays
inside the packet buffer; the deparser later appends that untouched payload
after the emitted headers.

## 3. Verify: validate the received IPv4 checksum

`VerifyIPv4Checksum` runs after parsing and before ingress. It calls the
`v1model` `verify_checksum` extern only when the IPv4 header is valid.

The tuple contains every fixed IPv4 header field except the existing checksum.
If the one's-complement calculation does not match, BMv2 sets
`standard_metadata.checksum_error` to 1. Verification reports the condition; it
does not automatically decide the forwarding policy.

That separation is useful: one program might drop a corrupt packet, while a
diagnostic program might count, clone, or report it.

## 4. Ingress safety gate: reject malformed input early

`IngressPipeline` resets its user metadata, counts the ingress port, and checks
the two error channels:

```p4
if (standard_metadata.parser_error != error.NoError ||
    standard_metadata.checksum_error == 1) {
    drop();
}
```

The `drop` action sets the lab's `meta.drop` flag and calls `mark_to_drop`.
Keeping a user flag is intentional: in `v1model`, `mark_to_drop` changes
`egress_spec` to the drop port. A later action could accidentally overwrite
that field. The explicit flag prevents subsequent forwarding tables from
running after a deny decision.

IPv4 packets with `TTL <= 1` are also dropped. A routed packet with a live TTL
continues through ACL, QoS, and routing. Non-IPv4 packets take the L2 path.

## 5. IPv4 policy: ACL first, QoS second

`ipv4_acl` matches source address, destination address, and IP protocol with
ternary masks. Ternary matching supports both exact policy and wildcards. Its
default action is `permit`, so an empty ACL does not block all IP traffic.

If an ACL entry calls `drop`, the metadata guard prevents every later ingress
table from running.

Permitted packets enter `qos_classifier`. It matches the IPv4 DiffServ byte and
writes `standard_metadata.priority`. On BMv2 this priority can influence queue
selection; this program also carries it into egress for an optional VLAN PCP
rewrite. The table defaults to `NoAction`, so the classifier is opt-in.

This ordering expresses a common policy rule: do not spend routing and QoS work
on traffic that is already denied.

## 6. IPv4 forwarding: LPM chooses direct routing or ECMP

`ipv4_lpm` performs longest-prefix matching on `hdr.ipv4.dst_addr`. A matching
entry chooses one of two forwarding forms.

### Direct route

`set_route` receives a next-hop MAC, router source MAC, and output port from the
control plane. It rewrites Ethernet, decrements IPv4 TTL, and writes
`standard_metadata.egress_spec`.

### ECMP route

`select_ecmp` receives a group ID and path count. It hashes IPv4 source,
destination, and protocol into `[0, path_count - 1]`, stores the group and hash
index in metadata, and decrements TTL.

`ecmp_nhop` then matches `(group, index)` and supplies the concrete MAC rewrite
and output port. Separating selection from next-hop resolution lets the control
plane change a group's members without changing the destination prefix.

The route and ECMP tables have direct packet-and-byte counters. A direct counter
is attached to a table entry, so it answers questions such as "how much traffic
used this prefix?" An indirect ingress-port counter uses the port number as its
explicit index.

Both route tables default to `drop`. A missing forwarding entry therefore fails
closed instead of leaking a packet to an arbitrary port.

## 7. Non-IPv4 forwarding: exact L2 lookup

ARP and other non-IPv4 Ethernet frames enter `l2_forward`, which matches the
destination MAC exactly. An entry may:

- select one output port with `forward_l2`;
- set `standard_metadata.mcast_grp` with `multicast`; or
- drop the frame.

The P4 program selects a multicast group but does not define its replicas. The
target's packet-replication engine is configured separately by the control
plane. That is why the example CLI file can select group 100 while group 100's
port list must be created as a separate runtime step.

## 8. End of ingress: BMv2 resolves the packet's disposition

After ingress, the `v1model` target examines architecture metadata. Depending
on the values, the packet may be dropped, sent to one output port, replicated,
cloned, resubmitted, or recirculated. This lab uses drop, unicast, and multicast
selection.

For a unicast packet, `egress_spec` is the requested port. BMv2 passes the
selected packet through its buffering and queueing logic, then presents the
actual chosen port as `standard_metadata.egress_port` during egress.

`egress_spec` is an ingress request; `egress_port` is the egress result. That
distinction becomes important for multicast because each replica has its own
egress port.

## 9. Egress: apply per-output behavior

`EgressPipeline` counts packets and bytes by the actual egress port. It then
runs two tables:

1. `egress_policy` can drop traffic for a selected output port. It defaults to
   `NoAction`.
2. `vlan_priority_rewrite`, used only when a VLAN header is valid, maps the
   internal priority to a VLAN PCP value.

Egress is the natural stage for decisions that depend on the final output port
or on a particular multicast replica. In contrast, ingress is the natural
stage for one-time routing and classification.

## 10. Update: repair the IPv4 checksum after mutation

Routing changed the TTL, so the received IPv4 checksum is no longer correct.
`UpdateIPv4Checksum` recalculates it after ingress and egress processing have
finished.

The position of this stage matters. Computing the checksum before the TTL
decrement would serialize an invalid packet. The checksum tuple must also match
the fields used during verification.

## 11. Deparse: serialize valid headers in wire order

`SwitchDeparser` emits headers in this order:

```text
Ethernet -> optional VLAN -> ARP or IPv4 -> optional TCP/UDP/ICMP
```

`packet.emit` outputs a header only when that header is valid. Therefore the
single ordered list correctly serializes an untagged ARP frame, a tagged IPv4
UDP packet, or an Ethernet frame with an unknown EtherType. The target appends
the original unparsed payload after the emitted headers.

The result is queued for transmission on the target-selected interface.

## 12. Four concrete paths to trace

### Valid IPv4 direct route

Parser validates Ethernet and IPv4, checksum verification succeeds, ACL
permits, QoS optionally classifies, LPM calls `set_route`, TTL is decremented,
egress counts the chosen port, checksum is repaired, and the frame is emitted.

### Valid IPv4 ECMP route

The first stages are identical, but LPM calls `select_ecmp`. The hash chooses a
member index, `ecmp_nhop` resolves it to a port and MAC pair, and the normal
egress/checksum/deparser sequence follows.

### ARP broadcast

The parser marks Ethernet and ARP valid. IPv4 checksum logic is skipped. The
L2 table selects a multicast group. BMv2 creates one replica per configured
egress port, and each replica independently passes through egress and deparsing.

### Bad IPv4 checksum

The parser succeeds, verification sets `checksum_error`, and the ingress safety
gate drops the packet before ACL or routing. No normal egress processing occurs.

## Table summary

| Stage | Table | Match | Main result | Default |
|---|---|---|---|---|
| Ingress | `ipv4_acl` | src, dst, protocol ternary | permit/drop | permit |
| Ingress | `qos_classifier` | DiffServ ternary | set priority | no action |
| Ingress | `ipv4_lpm` | destination IPv4 LPM | direct route/ECMP/drop | drop |
| Ingress | `ecmp_nhop` | group + index exact | next hop/drop | drop |
| Ingress | `l2_forward` | destination MAC exact | port/multicast/drop | drop |
| Egress | `egress_policy` | actual egress port exact | drop | no action |
| Egress | `vlan_priority_rewrite` | priority exact | rewrite VLAN PCP | no action |

## Architecture boundary

The six constructor arguments in `V1Switch` define the order used by this
target: parser, checksum verification, ingress, egress, checksum update, and
deparser. P4_16 itself is architecture-independent; another architecture may
expose different blocks, metadata, externs, and lifecycle rules.

For deeper reading, use the primary sources linked from the root README. In
particular, compare this program with `v1model.p4`, then read BMv2's
`simple_switch.md` for the target behavior that occurs between ingress and
egress.
