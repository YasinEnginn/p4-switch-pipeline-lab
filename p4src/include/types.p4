#ifndef P4_SWITCH_PIPELINE_TYPES_P4
#define P4_SWITCH_PIPELINE_TYPES_P4

typedef bit<9>  port_t;
typedef bit<12> vlan_id_t;
typedef bit<16> ether_type_t;
typedef bit<32> ipv4_addr_t;
typedef bit<48> mac_addr_t;

error {
    InvalidIPv4Version,
    IPv4OptionsNotSupported
}

header ethernet_t {
    mac_addr_t   dst_addr;
    mac_addr_t   src_addr;
    ether_type_t ether_type;
}

header vlan_t {
    bit<3>       pcp;
    bit<1>       dei;
    vlan_id_t    vlan_id;
    ether_type_t ether_type;
}

header arp_t {
    bit<16>     hardware_type;
    bit<16>     protocol_type;
    bit<8>      hardware_length;
    bit<8>      protocol_length;
    bit<16>     operation;
    mac_addr_t  sender_hardware_addr;
    ipv4_addr_t sender_protocol_addr;
    mac_addr_t  target_hardware_addr;
    ipv4_addr_t target_protocol_addr;
}

header ipv4_t {
    bit<4>      version;
    bit<4>      ihl;
    bit<8>      diffserv;
    bit<16>     total_length;
    bit<16>     identification;
    bit<3>      flags;
    bit<13>     fragment_offset;
    bit<8>      ttl;
    bit<8>      protocol;
    bit<16>     header_checksum;
    ipv4_addr_t src_addr;
    ipv4_addr_t dst_addr;
}

header tcp_t {
    bit<16> src_port;
    bit<16> dst_port;
    bit<32> sequence_number;
    bit<32> acknowledgement_number;
    bit<4>  data_offset;
    bit<3>  reserved;
    bit<1>  ns;
    bit<8>  flags;
    bit<16> window;
    bit<16> checksum;
    bit<16> urgent_pointer;
}

header udp_t {
    bit<16> src_port;
    bit<16> dst_port;
    bit<16> length;
    bit<16> checksum;
}

header icmp_t {
    bit<8>  type;
    bit<8>  code;
    bit<16> checksum;
    bit<32> rest_of_header;
}

struct headers_t {
    ethernet_t ethernet;
    vlan_t     vlan;
    arp_t      arp;
    ipv4_t     ipv4;
    tcp_t      tcp;
    udp_t      udp;
    icmp_t     icmp;
}

struct metadata_t {
    bit<1>  drop;
    bit<1>  use_ecmp;
    bit<16> ecmp_group;
    bit<16> ecmp_index;
}

#endif
