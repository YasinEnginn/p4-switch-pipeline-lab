#ifndef P4_SWITCH_PIPELINE_CHECKSUM_P4
#define P4_SWITCH_PIPELINE_CHECKSUM_P4

control VerifyIPv4Checksum(inout headers_t hdr, inout metadata_t meta) {
    apply {
        verify_checksum(
            hdr.ipv4.isValid(),
            {
                hdr.ipv4.version,
                hdr.ipv4.ihl,
                hdr.ipv4.diffserv,
                hdr.ipv4.total_length,
                hdr.ipv4.identification,
                hdr.ipv4.flags,
                hdr.ipv4.fragment_offset,
                hdr.ipv4.ttl,
                hdr.ipv4.protocol,
                hdr.ipv4.src_addr,
                hdr.ipv4.dst_addr
            },
            hdr.ipv4.header_checksum,
            HashAlgorithm.csum16);
    }
}

control UpdateIPv4Checksum(inout headers_t hdr, inout metadata_t meta) {
    apply {
        update_checksum(
            hdr.ipv4.isValid(),
            {
                hdr.ipv4.version,
                hdr.ipv4.ihl,
                hdr.ipv4.diffserv,
                hdr.ipv4.total_length,
                hdr.ipv4.identification,
                hdr.ipv4.flags,
                hdr.ipv4.fragment_offset,
                hdr.ipv4.ttl,
                hdr.ipv4.protocol,
                hdr.ipv4.src_addr,
                hdr.ipv4.dst_addr
            },
            hdr.ipv4.header_checksum,
            HashAlgorithm.csum16);
    }
}

#endif
