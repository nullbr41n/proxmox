#!/bin/bash
set -euo pipefail

REGION="${REGION:-proxmox}"
ZONE="${ZONE:-pve01}"
NODES="${NODES:-cp-0 cp-1 cp-2 worker-0 worker-1}"

for node in $NODES; do
  kubectl label node "$node" \
    "topology.kubernetes.io/region=${REGION}" \
    "topology.kubernetes.io/zone=${ZONE}" \
    --overwrite
done
