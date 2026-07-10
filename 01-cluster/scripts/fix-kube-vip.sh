#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TFVARS_FILE="${TFVARS_FILE:-${STACK_DIR}/terraform.tfvars}"

usage() {
  cat <<'EOF'
Patch kube-vip on live control-plane nodes for safer API VIP failover.

Run this ON EACH control-plane node (cp-0, cp-1, cp-2, ...) as root.

Usage:
  fix-kube-vip.sh [--vip <ip>] [--hostname <name>] [--interface <iface>] [--version <tag>]

Defaults are read from terraform.tfvars when present:
  kubeadm_control_plane_vip
  kubeadm_control_plane_hostname
  kube_vip_interface
  kube_vip_version
  kube_vip_lease_duration
  kube_vip_renew_deadline
  kube_vip_retry_period

What it does:
  1. Waits for the local apiserver on 127.0.0.1:6443
  2. Regenerates /etc/kubernetes/manifests/kube-vip.yaml with hardened settings
  3. Relaxes leader-election lease timings to avoid crash loops on slow API renewals
  4. Enables a watchdog that restarts kube-vip when the VIP is orphaned
EOF
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
  ' "${TFVARS_FILE}" 2>/dev/null || true
}

VIP=""
HOSTNAME=""
IFACE=""
VERSION=""
LEASE_DURATION=""
RENEW_DEADLINE=""
RETRY_PERIOD=""

patch_lease_timings() {
  local manifest="$1"
  sed -i "/name: vip_leaseduration/{n;s/value: \".*\"/value: \"${LEASE_DURATION}\"/}" "${manifest}"
  sed -i "/name: vip_renewdeadline/{n;s/value: \".*\"/value: \"${RENEW_DEADLINE}\"/}" "${manifest}"
  sed -i "/name: vip_retryperiod/{n;s/value: \".*\"/value: \"${RETRY_PERIOD}\"/}" "${manifest}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vip) VIP="${2:-}"; shift 2 ;;
    --hostname) HOSTNAME="${2:-}"; shift 2 ;;
    --interface) IFACE="${2:-}"; shift 2 ;;
    --version) VERSION="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "${VIP}" && -f "${TFVARS_FILE}" ]]; then VIP="$(tfvars_value kubeadm_control_plane_vip)"; fi
if [[ -z "${HOSTNAME}" && -f "${TFVARS_FILE}" ]]; then HOSTNAME="$(tfvars_value kubeadm_control_plane_hostname)"; fi
if [[ -z "${IFACE}" && -f "${TFVARS_FILE}" ]]; then IFACE="$(tfvars_value kube_vip_interface)"; fi
if [[ -z "${VERSION}" && -f "${TFVARS_FILE}" ]]; then VERSION="$(tfvars_value kube_vip_version)"; fi
if [[ -z "${LEASE_DURATION}" && -f "${TFVARS_FILE}" ]]; then LEASE_DURATION="$(tfvars_value kube_vip_lease_duration)"; fi
if [[ -z "${RENEW_DEADLINE}" && -f "${TFVARS_FILE}" ]]; then RENEW_DEADLINE="$(tfvars_value kube_vip_renew_deadline)"; fi
if [[ -z "${RETRY_PERIOD}" && -f "${TFVARS_FILE}" ]]; then RETRY_PERIOD="$(tfvars_value kube_vip_retry_period)"; fi

VIP="${VIP:-10.10.10.20}"
HOSTNAME="${HOSTNAME:-api.server.local}"
IFACE="${IFACE:-eth0}"
VERSION="${VERSION:-v1.0.4}"
LEASE_DURATION="${LEASE_DURATION:-30}"
RENEW_DEADLINE="${RENEW_DEADLINE:-15}"
RETRY_PERIOD="${RETRY_PERIOD:-3}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root on a control-plane node." >&2
  exit 1
fi

if [[ ! -f /etc/kubernetes/manifests/kube-vip.yaml ]]; then
  echo "This node does not look like a control-plane node (missing kube-vip manifest)." >&2
  exit 1
fi

echo "Waiting for local apiserver..."
for i in $(seq 1 60); do
  if curl -skf --connect-timeout 2 https://127.0.0.1:6443/livez >/dev/null 2>&1; then
    break
  fi
  if [[ "${i}" -eq 60 ]]; then
    echo "Local apiserver is not healthy. Fix kube-apiserver before patching kube-vip." >&2
    exit 1
  fi
  sleep 2
done

MANIFEST="/etc/kubernetes/manifests/kube-vip.yaml"

if [[ -x /usr/local/bin/install-kube-vip.sh ]]; then
  /usr/local/bin/install-kube-vip.sh "${IFACE}" "${VIP}" "${VERSION}" "${HOSTNAME}"
else
  echo "install-kube-vip.sh not found; applying inline manifest patch"
  if [[ -f /etc/kubernetes/super-admin.conf ]]; then
    sed -i '/- hostPath:/,/name: kubeconfig/ s|path: /etc/kubernetes/admin.conf|path: /etc/kubernetes/super-admin.conf|' "${MANIFEST}"
  fi
  grep -q "${HOSTNAME}" "${MANIFEST}" || sed -i "/- kubernetes/a\\    - ${HOSTNAME}" "${MANIFEST}"
  case "${VERSION}" in
    v1.*)
      grep -q 'vip_preserve_on_leadership_loss' "${MANIFEST}" || \
        sed -i '/name: vip_leaderelection/a\    - name: vip_preserve_on_leadership_loss\n      value: "true"' "${MANIFEST}"
      ;;
  esac
  sed -i "s|ghcr.io/kube-vip/kube-vip:.*|ghcr.io/kube-vip/kube-vip:${VERSION}\"|" "${MANIFEST}" || \
    sed -i "s|image: ghcr.io/kube-vip/kube-vip:.*|image: ghcr.io/kube-vip/kube-vip:${VERSION}|" "${MANIFEST}"
  touch "${MANIFEST}"
fi

patch_lease_timings "${MANIFEST}"
touch "${MANIFEST}"

install -d -m 0755 /usr/local/bin
cat >/etc/sysconfig/kube-vip-watchdog <<EOF
KUBE_VIP_ADDRESS=${VIP}
EOF

cat >/usr/local/bin/kube-vip-failover-watchdog.sh <<'WATCHDOG'
#!/bin/bash
set -euo pipefail

VIP="${KUBE_VIP_ADDRESS:?set in /etc/sysconfig/kube-vip-watchdog}"
COOLDOWN_FILE="/run/kube-vip-watchdog.last"
FAIL_FILE="/run/kube-vip-watchdog.failures"
COOLDOWN_SECS=60
FAIL_THRESHOLD=4

if [ -f "${COOLDOWN_FILE}" ]; then
  last="$(cat "${COOLDOWN_FILE}")"
  now="$(date +%s)"
  if [ "$((now - last))" -lt "${COOLDOWN_SECS}" ]; then
    exit 0
  fi
fi

if curl -skf --connect-timeout 5 "https://${VIP}:6443/livez" >/dev/null 2>&1; then
  echo 0 > "${FAIL_FILE}"
  exit 0
fi

if ip -4 addr show | grep -q "${VIP}/"; then
  echo 0 > "${FAIL_FILE}"
  exit 0
fi

if ! curl -skf --connect-timeout 5 https://127.0.0.1:6443/livez >/dev/null 2>&1; then
  echo 0 > "${FAIL_FILE}"
  exit 0
fi

failures=0
if [ -f "${FAIL_FILE}" ]; then
  failures="$(cat "${FAIL_FILE}")"
fi
failures="$((failures + 1))"
echo "${failures}" > "${FAIL_FILE}"

if [ "${failures}" -lt "${FAIL_THRESHOLD}" ]; then
  exit 0
fi

logger -t kube-vip-watchdog "VIP ${VIP} unreachable for ${failures} checks while local apiserver is healthy; restarting kube-vip"
echo 0 > "${FAIL_FILE}"
touch /etc/kubernetes/manifests/kube-vip.yaml
CID="$(crictl ps -a --name kube-vip -q 2>/dev/null | head -1 || true)"
if [ -n "${CID}" ]; then
  crictl stop "${CID}" >/dev/null 2>&1 || true
fi
date +%s > "${COOLDOWN_FILE}"
WATCHDOG
chmod 0700 /usr/local/bin/kube-vip-failover-watchdog.sh

cat >/etc/systemd/system/kube-vip-failover-watchdog.service <<'UNIT'
[Unit]
Description=Restart kube-vip when the API VIP is orphaned
ConditionPathExists=/etc/kubernetes/manifests/kube-vip.yaml

[Service]
Type=oneshot
EnvironmentFile=-/etc/sysconfig/kube-vip-watchdog
ExecStart=/usr/local/bin/kube-vip-failover-watchdog.sh
UNIT

cat >/etc/systemd/system/kube-vip-failover-watchdog.timer <<'TIMER'
[Unit]
Description=Check for orphaned kube-vip API VIP every 15 seconds

[Timer]
OnBootSec=60
OnUnitActiveSec=15
AccuracySec=1

[Install]
WantedBy=timers.target
TIMER

systemctl daemon-reload
systemctl enable --now kube-vip-failover-watchdog.timer

echo "kube-vip patched. VIP=${VIP} version=${VERSION}"
sleep 5
ip -4 addr show | grep "${VIP}" || echo "VIP not on this node yet (may be on another control-plane node)"
