#ifndef P4_SWITCH_PIPELINE_INGRESS_P4
#define P4_SWITCH_PIPELINE_INGRESS_P4

control IngressPipeline(
    inout headers_t hdr,
    inout metadata_t meta,
    inout standard_metadata_t standard_metadata)
{
    counter(PORT_COUNTER_SIZE, CounterType.packets_and_bytes) ingress_port_counter;
    direct_counter(CounterType.packets_and_bytes) ipv4_route_counter;
    direct_counter(CounterType.packets_and_bytes) ecmp_nhop_counter;
    direct_counter(CounterType.packets_and_bytes) l2_forward_counter;

    action drop() {
        meta.drop = 1;
        mark_to_drop(standard_metadata);
    }

    action permit() {
        meta.drop = 0;
    }

    action set_priority(bit<3> priority) {
        standard_metadata.priority = priority;
    }

    action set_route(mac_addr_t dst_mac, mac_addr_t src_mac, port_t port) {
        hdr.ethernet.dst_addr = dst_mac;
        hdr.ethernet.src_addr = src_mac;
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
        standard_metadata.egress_spec = port;
        meta.use_ecmp = 0;
    }

    action select_ecmp(bit<16> group_id, bit<16> path_count) {
        meta.use_ecmp = 1;
        meta.ecmp_group = group_id;
        hash(
            meta.ecmp_index,
            HashAlgorithm.crc16,
            (bit<16>) 0,
            {
                hdr.ipv4.src_addr,
                hdr.ipv4.dst_addr,
                hdr.ipv4.protocol
            },
            path_count);
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    }

    action set_ecmp_nhop(mac_addr_t dst_mac, mac_addr_t src_mac, port_t port) {
        hdr.ethernet.dst_addr = dst_mac;
        hdr.ethernet.src_addr = src_mac;
        standard_metadata.egress_spec = port;
    }

    action forward_l2(port_t port) {
        standard_metadata.egress_spec = port;
    }

    action multicast(bit<16> group_id) {
        standard_metadata.mcast_grp = group_id;
    }

    table ipv4_acl {
        key = {
            hdr.ipv4.src_addr: ternary;
            hdr.ipv4.dst_addr: ternary;
            hdr.ipv4.protocol: ternary;
        }
        actions = {
            permit;
            drop;
        }
        size = 256;
        default_action = permit();
    }

    table qos_classifier {
        key = {
            hdr.ipv4.diffserv: ternary;
        }
        actions = {
            set_priority;
            NoAction;
        }
        size = 64;
        default_action = NoAction();
    }

    table ipv4_lpm {
        key = {
            hdr.ipv4.dst_addr: lpm;
        }
        actions = {
            set_route;
            select_ecmp;
            drop;
        }
        counters = ipv4_route_counter;
        size = 1024;
        default_action = drop();
    }

    table ecmp_nhop {
        key = {
            meta.ecmp_group: exact;
            meta.ecmp_index: exact;
        }
        actions = {
            set_ecmp_nhop;
            drop;
        }
        counters = ecmp_nhop_counter;
        size = 256;
        default_action = drop();
    }

    table l2_forward {
        key = {
            hdr.ethernet.dst_addr: exact;
        }
        actions = {
            forward_l2;
            multicast;
            drop;
        }
        counters = l2_forward_counter;
        size = 1024;
        default_action = drop();
    }

    apply {
        meta.drop = 0;
        meta.use_ecmp = 0;
        meta.ecmp_group = 0;
        meta.ecmp_index = 0;

        ingress_port_counter.count((bit<32>) standard_metadata.ingress_port);

        if (standard_metadata.parser_error != error.NoError ||
            standard_metadata.checksum_error == 1) {
            drop();
        } else if (hdr.ipv4.isValid()) {
            if (hdr.ipv4.ttl <= 1) {
                drop();
            } else {
                ipv4_acl.apply();

                if (meta.drop == 0) {
                    qos_classifier.apply();
                    ipv4_lpm.apply();

                    if (meta.drop == 0 && meta.use_ecmp == 1) {
                        ecmp_nhop.apply();
                    }
                }
            }
        } else {
            l2_forward.apply();
        }
    }
}

#endif
