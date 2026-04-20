#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TFVARS_FILE="${TFVARS_FILE:-${STACK_DIR}/terraform.tfvars}"

usage() {
  cat <<'EOF'
Usage:
  replace-control-plane.sh <cp-0|cp-1|cp-2|cp-3|cp-4> [--survivor <healthy-cp-ip-or-hostname>] [--ssh-user <user>] [--auto-approve] [--force]

What it does:
  1. Reads the stack tfvars to determine the target control-plane node identity.
  2. Auto-detects a survivor by default. A survivor means a healthy remaining control-plane node that still has API and join-server access.
  3. Verifies the surviving cluster looks healthy enough for a replacement.
  4. Removes a stale etcd member for the target hostname/IP on the healthy survivor.
  5. Forces Terraform to replace the target node with cp0_bootstrap_mode=join.

Examples:
  ./scripts/replace-control-plane.sh cp-0
  ./scripts/replace-control-plane.sh cp-1 --survivor cp-2 --ssh-user rocky --auto-approve
  ./scripts/replace-control-plane.sh cp-0 --survivor 10.10.10.22 --force
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

tfvars_value() {
  local key="$1"
  awk -F= -v key="$key" '
    $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
      value = $2
      sub(/#.*/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^"/, "", value)
      gsub(/"$/, "", value)
      print value
      exit
    }
  ' "${TFVARS_FILE}"
}

tfvars_list_numbers() {
  local key="$1"
  awk -F= -v key="$key" '
    $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
      value = $2
      sub(/#.*/, "", value)
      gsub(/[\[\],]/, " ", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "${TFVARS_FILE}"
}

TARGET=""
SURVIVOR=""
SSH_USER="rocky"
AUTO_APPROVE=0
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    cp-[0-4])
      if [[ -n "${TARGET}" ]]; then
        echo "Target already set to ${TARGET}, got unexpected extra target $1" >&2
        exit 1
      fi
      TARGET="$1"
      shift
      ;;
    --survivor)
      SURVIVOR="${2:-}"
      shift 2
      ;;
    --ssh-user)
      SSH_USER="${2:-}"
      shift 2
      ;;
    --auto-approve)
      AUTO_APPROVE=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "${TARGET}" ]]; then
  echo "Target node is required" >&2
  usage >&2
  exit 1
fi

require_cmd ssh
require_cmd ssh-keygen
require_cmd terraform
require_cmd python3

if [[ ! -f "${TFVARS_FILE}" ]]; then
  echo "terraform.tfvars not found: ${TFVARS_FILE}" >&2
  exit 1
fi

VIP="$(tfvars_value kubeadm_control_plane_vip)"
BASE_OCTET="$(tfvars_value control_plane_base_octet)"
ENABLED_SLOTS_RAW="$(tfvars_list_numbers enabled_control_plane_slots)"

if [[ -z "${VIP}" || -z "${BASE_OCTET}" || -z "${ENABLED_SLOTS_RAW}" ]]; then
  echo "Failed to read required control-plane settings from ${TFVARS_FILE}" >&2
  exit 1
fi

TARGET_SLOT="${TARGET#cp-}"
IFS='.' read -r o1 o2 o3 _ <<<"${VIP}"
TARGET_IP="${o1}.${o2}.${o3}.$((BASE_OCTET + TARGET_SLOT + 1))"

read -r -a ENABLED_SLOTS <<<"${ENABLED_SLOTS_RAW}"
TARGET_ENABLED=0
SURVIVOR_CANDIDATES=()
for slot in "${ENABLED_SLOTS[@]}"; do
  if [[ "${slot}" == "${TARGET_SLOT}" ]]; then
    TARGET_ENABLED=1
    continue
  fi
  SURVIVOR_CANDIDATES+=("${o1}.${o2}.${o3}.$((BASE_OCTET + slot + 1))")
done

if [[ "${TARGET_ENABLED}" -ne 1 ]]; then
  echo "${TARGET} is not currently enabled in enabled_control_plane_slots. Refusing." >&2
  exit 1
fi

if [[ -n "${SURVIVOR}" && ( "${SURVIVOR}" == "${TARGET}" || "${SURVIVOR}" == "${TARGET_IP}" ) ]]; then
  echo "--survivor must be a different healthy control-plane node, not the target being replaced." >&2
  exit 1
fi

ENABLED_COUNT="${#ENABLED_SLOTS[@]}"
if (( FORCE == 0 && ENABLED_COUNT <= 2 )); then
  echo "Refusing to replace ${TARGET}: only ${ENABLED_COUNT} control-plane slots are enabled, so replacement risks losing quorum. Use --force if this is intentional." >&2
  exit 1
fi

for candidate in "${SURVIVOR_CANDIDATES[@]}"; do
  ssh-keygen -R "${candidate}" >/dev/null 2>&1 || true
done

read -r -d '' REMOTE_CHECK <<"EOF" || true
set -euo pipefail
TARGET_NAME="$1"
TARGET_IP="$2"
FORCE="$3"

if [ -f /usr/local/bin/cleanup-etcd.py ]; then
  python3 - <<'PY'
from pathlib import Path
path = Path("/usr/local/bin/cleanup-etcd.py")
data = path.read_text()
old = """          probe = subprocess.run(
              etcd + [\"endpoint\", \"health\", f\"--endpoints={member['client']}\"],
              capture_output=True,
              env=env,
              timeout=5,
          )
          if probe.returncode != 0:
              subprocess.run(etcd + [\"member\", \"remove\", member[\"id\"]], capture_output=True, env=env, timeout=20)
"""
new = """          try:
              probe = subprocess.run(
                  etcd + [\"endpoint\", \"health\", f\"--endpoints={member['client']}\"],
                  capture_output=True,
                  env=env,
                  timeout=5,
              )
              unhealthy = probe.returncode != 0
          except subprocess.TimeoutExpired:
              unhealthy = True
          if unhealthy:
              subprocess.run(etcd + [\"member\", \"remove\", member[\"id\"]], capture_output=True, env=env, timeout=20)
"""
if old in data and new not in data:
    path.write_text(data.replace(old, new))
PY
fi

KCFG=""
if [ -f /etc/kubernetes/super-admin.conf ]; then
  KCFG=/etc/kubernetes/super-admin.conf
elif [ -f /etc/kubernetes/admin.conf ]; then
  KCFG=/etc/kubernetes/admin.conf
else
  echo "No kubeconfig found on survivor" >&2
  exit 10
fi

SELF_IP="$(ip -4 -o addr show scope global | awk '{print $4}' | cut -d/ -f1 | head -n1)"
if [ -z "$SELF_IP" ]; then
  echo "Unable to determine survivor IP" >&2
  exit 11
fi

TMP_KCFG="$(mktemp)"
cp "$KCFG" "$TMP_KCFG"
sed -i "s|server: .*|server: https://${SELF_IP}:6443|" "$TMP_KCFG"
export KUBECONFIG="$TMP_KCFG"

cleanup() {
  rm -f "$TMP_KCFG"
}
trap cleanup EXIT

kubectl version >/dev/null 2>&1 || {
  echo "kubectl cannot reach the survivor API on ${SELF_IP}:6443" >&2
  exit 12
}

JOIN_TEXT="$(curl -sf "http://127.0.0.1:8080/join-cp.txt" || true)"
if [ -z "$JOIN_TEXT" ]; then
  echo "join-server is not serving join-cp.txt on the survivor" >&2
  exit 13
fi

READY_COUNT="$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{range .status.conditions[?(@.type=="Ready")]}{.status}{end}{" "}{.metadata.labels.node-role\.kubernetes\.io/control-plane}{"\n"}{end}' | awk '$2=="True" && ($3=="" || $3=="true") {count++} END {print count+0}')"
if [ "${FORCE}" != "1" ] && [ "${READY_COUNT}" -lt 2 ]; then
  echo "Only ${READY_COUNT} ready control-plane nodes detected on the survivor view. Refusing without --force." >&2
  exit 14
fi

ETCD_READY_COUNT="$(kubectl get pods -n kube-system -l component=etcd -o jsonpath='{range .items[*]}{.metadata.name}{" "}{range .status.containerStatuses[*]}{.ready}{" "}{end}{"\n"}{end}' | awk '$2=="true" {count++} END {print count+0}')"
if [ "${FORCE}" != "1" ] && [ "${ETCD_READY_COUNT}" -lt 2 ]; then
  echo "Only ${ETCD_READY_COUNT} ready etcd pods detected. Refusing without --force." >&2
  exit 15
fi

/usr/bin/python3 /usr/local/bin/cleanup-etcd.py "$TARGET_NAME" "$TARGET_IP"
echo "Survivor-side preflight and stale etcd cleanup completed."
EOF

run_remote_check() {
  local survivor="$1"
  ssh -o StrictHostKeyChecking=no "${SSH_USER}@${survivor}" \
    "sudo bash -s -- '${TARGET}' '${TARGET_IP}' '${FORCE}'" <<<"${REMOTE_CHECK}"
}

if [[ -z "${SURVIVOR}" ]]; then
  for candidate in "${SURVIVOR_CANDIDATES[@]}"; do
    echo "Trying survivor candidate: ${SSH_USER}@${candidate}"
    if run_remote_check "${candidate}"; then
      SURVIVOR="${candidate}"
      break
    fi
  done
  if [[ -z "${SURVIVOR}" ]]; then
    echo "Unable to auto-detect a healthy survivor for ${TARGET}. Pass --survivor explicitly or use --force after manual verification." >&2
    exit 1
  fi
else
  run_remote_check "${SURVIVOR}"
fi

echo "Target: ${TARGET} (${TARGET_IP})"
echo "Survivor: ${SSH_USER}@${SURVIVOR}"

if [[ "${TARGET}" == "cp-0" ]]; then
  FILE_REPLACE='-replace=proxmox_virtual_environment_file.cloud_init_cp0'
  VM_REPLACE='-replace=module.control_plane_bootstrap[0].proxmox_virtual_environment_vm.vm["cp-0"]'
  MODE_VAR='-var=cp0_bootstrap_mode=join'
else
  FILE_REPLACE="-replace=proxmox_virtual_environment_file.cloud_init_control_plane[\"${TARGET}\"]"
  VM_REPLACE="-replace=module.control_plane_join_${TARGET_SLOT}[0].proxmox_virtual_environment_vm.vm[\"${TARGET}\"]"
  MODE_VAR='-var=cp0_bootstrap_mode=init'
fi

echo "Replacing ${TARGET}"

TF_ARGS=(
  apply
  "${MODE_VAR}"
  "${FILE_REPLACE}"
  "${VM_REPLACE}"
)

if [[ "${AUTO_APPROVE}" -eq 1 ]]; then
  TF_ARGS+=("-auto-approve")
fi

(
  cd "${STACK_DIR}"
  terraform "${TF_ARGS[@]}"
)
