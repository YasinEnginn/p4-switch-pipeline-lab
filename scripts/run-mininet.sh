#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image_name="${P4_LAB_IMAGE:-p4-switch-pipeline-lab:mininet}"

mkdir -p "${repo_dir}/artifacts"

docker build \
    --file "${repo_dir}/mininet/Dockerfile" \
    --tag "${image_name}" \
    "${repo_dir}"

tty_args=()
if [[ -t 0 && -t 1 ]]; then
    tty_args=(-it)
fi

docker run --rm \
    "${tty_args[@]}" \
    --privileged \
    --hostname p4-mininet-lab \
    --env "LAB_HOST_UID=$(id -u)" \
    --env "LAB_HOST_GID=$(id -g)" \
    --mount "type=bind,src=${repo_dir}/artifacts,dst=/workspace/artifacts" \
    "${image_name}" \
    "$@"
