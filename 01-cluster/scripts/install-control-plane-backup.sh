#!/usr/bin/env bash
# Install control-plane etcd/PKI backup timer on an already-running CP node.
# Safe to re-run. Uses NFS mount at /mnt/backup by default.
#
# Usage (on a control-plane node as root):
#   CLUSTER_BACKUP_NAME=khet ./install-control-plane-backup.sh
#   ./install-control-plane-backup.sh --run-now
#
# Or from a laptop with SSH:
#   scp scripts/install-control-plane-backup.sh rocky@10.10.11.21:/tmp/
#   ssh rocky@10.10.11.21 'sudo CLUSTER_BACKUP_NAME=khet bash /tmp/install-control-plane-backup.sh --run-now'

set -euo pipefail

RUN_NOW=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-now) RUN_NOW=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root" >&2
  exit 1
fi

CLUSTER_BACKUP_ENABLED="${CLUSTER_BACKUP_ENABLED:-true}"
CLUSTER_BACKUP_NAME="${CLUSTER_BACKUP_NAME:-khet}"
CLUSTER_BACKUP_MOUNT="${CLUSTER_BACKUP_MOUNT:-/mnt/backup}"
CLUSTER_BACKUP_KEEP_DAILY="${CLUSTER_BACKUP_KEEP_DAILY:-7}"
CLUSTER_BACKUP_KEEP_WEEKLY="${CLUSTER_BACKUP_KEEP_WEEKLY:-4}"
CLUSTER_BACKUP_ON_CALENDAR="${CLUSTER_BACKUP_ON_CALENDAR:-*-*-* 03:15:00}"

cat >/etc/sysconfig/k8s-control-plane-backup <<EOF
CLUSTER_BACKUP_ENABLED=${CLUSTER_BACKUP_ENABLED}
CLUSTER_BACKUP_NAME=${CLUSTER_BACKUP_NAME}
CLUSTER_BACKUP_MOUNT=${CLUSTER_BACKUP_MOUNT}
CLUSTER_BACKUP_KEEP_DAILY=${CLUSTER_BACKUP_KEEP_DAILY}
CLUSTER_BACKUP_KEEP_WEEKLY=${CLUSTER_BACKUP_KEEP_WEEKLY}
EOF

cat >/usr/local/bin/backup-control-plane.sh <<'EOF'
#!/bin/bash
set -euo pipefail

ENV_FILE="/etc/sysconfig/k8s-control-plane-backup"
if [ -f "${ENV_FILE}" ]; then
  # shellcheck disable=SC1090
  . "${ENV_FILE}"
fi

if [ "${CLUSTER_BACKUP_ENABLED:-true}" != "true" ]; then
  echo "cluster backup disabled"
  exit 0
fi

if [ ! -f /etc/kubernetes/admin.conf ] && [ ! -f /etc/kubernetes/super-admin.conf ]; then
  echo "not a control-plane node; skipping"
  exit 0
fi

if [ -f /etc/kubernetes/super-admin.conf ]; then
  export KUBECONFIG=/etc/kubernetes/super-admin.conf
else
  export KUBECONFIG=/etc/kubernetes/admin.conf
fi

MOUNT_POINT="${CLUSTER_BACKUP_MOUNT:-/mnt/backup}"
SITE="${CLUSTER_BACKUP_NAME:-cluster}"
KEEP_DAILY="${CLUSTER_BACKUP_KEEP_DAILY:-7}"
KEEP_WEEKLY="${CLUSTER_BACKUP_KEEP_WEEKLY:-4}"
ROOT="${MOUNT_POINT}/k8s/cluster/${SITE}"
DAILY_ROOT="${ROOT}/daily"
WEEKLY_ROOT="${ROOT}/weekly"
LOCK_FILE="${ROOT}/.backup.lock"
LOG_TAG="k8s-control-plane-backup"

if ! mountpoint -q "${MOUNT_POINT}"; then
  echo "${LOG_TAG}: ${MOUNT_POINT} is not mounted" >&2
  exit 1
fi

ETCD_POD="$(kubectl get pods -n kube-system -l component=etcd --field-selector spec.nodeName="$(hostname)" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [ -z "${ETCD_POD}" ]; then
  echo "${LOG_TAG}: no local etcd pod on $(hostname); leaving lock for another CP"
  exit 0
fi

mkdir -p "${DAILY_ROOT}" "${WEEKLY_ROOT}"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
  echo "${LOG_TAG}: another control-plane is already backing up; exiting"
  exit 0
fi

TS="$(date -u +%F-%H%M%S)"
DEST="${DAILY_ROOT}/${TS}"
TMP="${DEST}.tmp"
rm -rf "${TMP}"
mkdir -p "${TMP}"

echo "${LOG_TAG}: starting backup to ${DEST}"

kubectl exec -n kube-system "${ETCD_POD}" -- \
  etcdctl \
  --cert=/etc/kubernetes/pki/etcd/peer.crt \
  --key=/etc/kubernetes/pki/etcd/peer.key \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  snapshot save /var/lib/etcd/snapshot.db

# etcd data is hostPath-mounted; avoid kubectl cp (image has no tar)
cp -a /var/lib/etcd/snapshot.db "${TMP}/snapshot.db"
rm -f /var/lib/etcd/snapshot.db || true

if command -v etcdutl >/dev/null 2>&1; then
  etcdutl snapshot status "${TMP}/snapshot.db" -w table | tee "${TMP}/snapshot-status.txt"
else
  echo "etcdutl not installed; snapshot status skipped" >"${TMP}/snapshot-status.txt"
fi

TAR_PATHS="etc/kubernetes/pki etc/kubernetes/manifests etc/kubernetes/admin.conf etc/kubernetes/controller-manager.conf etc/kubernetes/scheduler.conf etc/kubernetes/kubelet.conf"
if [ -f /etc/kubernetes/super-admin.conf ]; then
  TAR_PATHS="${TAR_PATHS} etc/kubernetes/super-admin.conf"
fi
# shellcheck disable=SC2086
tar -C / -czf "${TMP}/k8s-control-plane-files.tgz" ${TAR_PATHS}

{
  echo "site=${SITE}"
  echo "hostname=$(hostname)"
  echo "timestamp=${TS}"
  echo "etcd_pod=${ETCD_POD}"
} >"${TMP}/META.txt"

mv "${TMP}" "${DEST}"

if [ "$(date -u +%u)" = "7" ]; then
  cp -a "${DEST}" "${WEEKLY_ROOT}/${TS}"
fi

ls -1dt "${DAILY_ROOT}"/*/ 2>/dev/null | tail -n +"$((KEEP_DAILY + 1))" | xargs -r rm -rf
ls -1dt "${WEEKLY_ROOT}"/*/ 2>/dev/null | tail -n +"$((KEEP_WEEKLY + 1))" | xargs -r rm -rf

echo "${LOG_TAG}: completed ${DEST}"
ls -lh "${DEST}"
EOF
chmod 700 /usr/local/bin/backup-control-plane.sh

cat >/etc/systemd/system/k8s-control-plane-backup.service <<'EOF'
[Unit]
Description=Backup Kubernetes etcd snapshot and control-plane files
After=network-online.target kubelet.service
ConditionPathExistsGlob=/etc/kubernetes/*admin.conf

[Service]
Type=oneshot
EnvironmentFile=-/etc/sysconfig/k8s-control-plane-backup
ExecStart=/usr/local/bin/backup-control-plane.sh
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF

cat >/etc/systemd/system/k8s-control-plane-backup.timer <<EOF
[Unit]
Description=Daily Kubernetes control-plane backup
ConditionPathExistsGlob=/etc/kubernetes/*admin.conf

[Timer]
OnCalendar=${CLUSTER_BACKUP_ON_CALENDAR}
Persistent=true
RandomizedDelaySec=300
Unit=k8s-control-plane-backup.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
if [[ "${CLUSTER_BACKUP_ENABLED}" == "true" ]]; then
  systemctl enable --now k8s-control-plane-backup.timer
  systemctl status --no-pager k8s-control-plane-backup.timer || true
else
  systemctl disable --now k8s-control-plane-backup.timer 2>/dev/null || true
fi

echo "Installed control-plane backup -> ${CLUSTER_BACKUP_MOUNT}/k8s/cluster/${CLUSTER_BACKUP_NAME}/{daily,weekly}"

if [[ "${RUN_NOW}" -eq 1 ]]; then
  echo "Running backup now..."
  systemctl start k8s-control-plane-backup.service
  systemctl status --no-pager k8s-control-plane-backup.service || true
  ls -lah "${CLUSTER_BACKUP_MOUNT}/k8s/cluster/${CLUSTER_BACKUP_NAME}/daily" || true
fi
