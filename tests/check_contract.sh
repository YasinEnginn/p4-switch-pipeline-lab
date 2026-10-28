#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
p4info_file="${repo_dir}/build/switch.p4info.txtpb"
json_file="${repo_dir}/build/switch.json"

if [[ ! -s "${p4info_file}" || ! -s "${json_file}" ]]; then
    echo "Build artifacts are missing. Run 'make compile' first." >&2
    exit 1
fi

required_entities=(
    'IngressPipeline.ipv4_acl'
    'IngressPipeline.qos_classifier'
    'IngressPipeline.ipv4_lpm'
    'IngressPipeline.ecmp_nhop'
    'IngressPipeline.l2_forward'
    'EgressPipeline.egress_policy'
    'EgressPipeline.vlan_priority_rewrite'
    'IngressPipeline.ingress_port_counter'
    'EgressPipeline.egress_port_counter'
)

for entity in "${required_entities[@]}"; do
    if ! grep -Fq "name: \"${entity}\"" "${p4info_file}"; then
        echo "Generated P4Info is missing ${entity}." >&2
        exit 1
    fi
done

echo "P4Info contract check passed (${#required_entities[@]} entities)."
