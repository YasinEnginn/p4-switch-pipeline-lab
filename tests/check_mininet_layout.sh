#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

required_files=(
    "mininet/Dockerfile"
    "mininet/lab.py"
    "mininet/udp_probe.py"
    "control-plane/mininet/s1-commands.txt"
    "control-plane/mininet/s2-commands.txt"
    "control-plane/mininet/s3-commands.txt"
    "scripts/run-mininet.sh"
)

for relative_path in "${required_files[@]}"; do
    [[ -s "${repo_dir}/${relative_path}" ]] || {
        echo "Missing Mininet lab file: ${relative_path}" >&2
        exit 1
    }
done

for switch_name in s1 s2 s3; do
    command_file="${repo_dir}/control-plane/mininet/${switch_name}-commands.txt"
    route_count="$(grep -c 'table_add IngressPipeline.ipv4_lpm' "${command_file}")"
    [[ "${route_count}" -eq 3 ]] || {
        echo "${switch_name} must contain exactly three IPv4 routes." >&2
        exit 1
    }
done

python3 -m py_compile \
    "${repo_dir}/mininet/lab.py" \
    "${repo_dir}/mininet/udp_probe.py"

echo "Mininet layout check passed."
