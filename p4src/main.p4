// SPDX-License-Identifier: MIT
// A complete, educational P4_16 pipeline for the BMv2 v1model target.

#include <core.p4>
#include <v1model.p4>

#include "include/constants.p4"
#include "include/types.p4"
#include "include/parser.p4"
#include "include/checksum.p4"
#include "include/ingress.p4"
#include "include/egress.p4"
#include "include/deparser.p4"

V1Switch(
    SwitchParser(),
    VerifyIPv4Checksum(),
    IngressPipeline(),
    EgressPipeline(),
    UpdateIPv4Checksum(),
    SwitchDeparser()
) main;
