#ifndef P4_SWITCH_PIPELINE_EGRESS_P4
#define P4_SWITCH_PIPELINE_EGRESS_P4

control EgressPipeline(
    inout headers_t hdr,
    inout metadata_t meta,
    inout standard_metadata_t standard_metadata)
{
    counter(PORT_COUNTER_SIZE, CounterType.packets_and_bytes) egress_port_counter;

    action drop() {
        mark_to_drop(standard_metadata);
    }

    action rewrite_vlan_pcp(bit<3> pcp) {
        hdr.vlan.pcp = pcp;
    }

    table egress_policy {
        key = {
            standard_metadata.egress_port: exact;
        }
        actions = {
            drop;
            NoAction;
        }
        size = 64;
        default_action = NoAction();
    }

    table vlan_priority_rewrite {
        key = {
            standard_metadata.priority: exact;
        }
        actions = {
            rewrite_vlan_pcp;
            NoAction;
        }
        size = 8;
        default_action = NoAction();
    }

    apply {
        egress_port_counter.count((bit<32>) standard_metadata.egress_port);
        egress_policy.apply();

        if (hdr.vlan.isValid()) {
            vlan_priority_rewrite.apply();
        }
    }
}

#endif
