#ifndef P4_SWITCH_PIPELINE_DEPARSER_P4
#define P4_SWITCH_PIPELINE_DEPARSER_P4

control SwitchDeparser(packet_out packet, in headers_t hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.vlan);
        packet.emit(hdr.arp);
        packet.emit(hdr.ipv4);
        packet.emit(hdr.tcp);
        packet.emit(hdr.udp);
        packet.emit(hdr.icmp);
    }
}

#endif
