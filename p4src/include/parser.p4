#ifndef P4_SWITCH_PIPELINE_PARSER_P4
#define P4_SWITCH_PIPELINE_PARSER_P4

parser SwitchParser(
    packet_in packet,
    out headers_t hdr,
    inout metadata_t meta,
    inout standard_metadata_t standard_metadata)
{
    state start {
        transition parse_ethernet;
    }

    state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.ether_type) {
            ETHERTYPE_VLAN: parse_vlan;
            ETHERTYPE_ARP:  parse_arp;
            ETHERTYPE_IPV4: parse_ipv4;
            default:        accept;
        }
    }

    state parse_vlan {
        packet.extract(hdr.vlan);
        transition select(hdr.vlan.ether_type) {
            ETHERTYPE_ARP:  parse_arp;
            ETHERTYPE_IPV4: parse_ipv4;
            default:        accept;
        }
    }

    state parse_arp {
        packet.extract(hdr.arp);
        transition accept;
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        verify(hdr.ipv4.version == 4, error.InvalidIPv4Version);
        verify(hdr.ipv4.ihl == 5, error.IPv4OptionsNotSupported);
        transition select(hdr.ipv4.protocol) {
            IP_PROTOCOL_TCP:  parse_tcp;
            IP_PROTOCOL_UDP:  parse_udp;
            IP_PROTOCOL_ICMP: parse_icmp;
            default:          accept;
        }
    }

    state parse_tcp {
        packet.extract(hdr.tcp);
        transition accept;
    }

    state parse_udp {
        packet.extract(hdr.udp);
        transition accept;
    }

    state parse_icmp {
        packet.extract(hdr.icmp);
        transition accept;
    }
}

#endif
