# Manual Backup And Restore

This document describes a clean manual backup and restore workflow for the kubeadm stacked-etcd control plane used by this stack.

Use this when you want a recovery path that does not depend on Proxmox snapshots.

## Automated Daily Backup

Control-plane nodes run `k8s-control-plane-backup.timer` (cloud-init on new nodes, or `scripts/install-control-plane-backup.sh` on existing ones).

Output layout:

```text
/mnt/backup/k8s/cluster/<site>/{daily,weekly}/<timestamp>/
  snapshot.db
  k8s-control-plane-files.tgz
  META.txt
```

`<site>` defaults to `kubernetes_topology_zone` (e.g. `khet`, `bhado`). Only one CP performs each run (NFS flock).

The manual procedure below is still the restore path after quorum loss; automation only covers taking backups.

## Scope

This covers:

- manual backup of etcd state
- backup of Kubernetes control-plane files
- manual restore after quorum loss

This is for disaster recovery, not routine node replacement.

For normal replacement when quorum still exists, use:

```bash
./scripts/replace-control-plane.sh cp-0
./scripts/replace-control-plane.sh cp-1
./scripts/replace-control-plane.sh cp-2
```

## When To Use This

Use this manual restore path when:

- stacked etcd quorum is lost
- normal `kubeadm join --control-plane` recovery is no longer enough
- you have a valid etcd snapshot and control-plane file backup

Examples:

- only 1 of 3 etcd members survives
- multiple control-plane nodes are lost at once
- etcd state is corrupted or unrecoverable through normal member replacement

## What To Back Up

Back up all of the following from a healthy control-plane node:

- etcd snapshot
- `/etc/kubernetes/pki`
- `/etc/kubernetes/manifests`
- kubeconfig files in `/etc/kubernetes/*.conf`

These files together give you:

- cluster data from etcd
- PKI and control-plane certificates
- static pod manifests for etcd, apiserver, controller-manager, scheduler
- kubeconfigs needed by control-plane components

## Backup Procedure

Run this on a healthy control-plane node, ideally `cp-1` or `cp-2`.

```bash
sudo mkdir -p /root/cluster-backup/$(date +%F-%H%M)
BACKUP_DIR=/root/cluster-backup/$(date +%F-%H%M)

export KUBECONFIG=/etc/kubernetes/admin.conf

ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n kube-system "$ETCD_POD" -- \
  etcdctl \
  --cert=/etc/kubernetes/pki/etcd/peer.crt \
  --key=/etc/kubernetes/pki/etcd/peer.key \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  snapshot save /var/lib/etcd/snapshot.db

kubectl cp \
  kube-system/${ETCD_POD}:/var/lib/etcd/snapshot.db \
  "${BACKUP_DIR}/snapshot.db"

sudo tar -C / -czf "${BACKUP_DIR}/k8s-control-plane-files.tgz" \
  etc/kubernetes/pki \
  etc/kubernetes/manifests \
  etc/kubernetes/admin.conf \
  etc/kubernetes/controller-manager.conf \
  etc/kubernetes/scheduler.conf \
  etc/kubernetes/kubelet.conf

sudo etcdutl snapshot status "${BACKUP_DIR}/snapshot.db" -w table
ls -lh "${BACKUP_DIR}"
```

Then copy the backup directory off-cluster.

Do not leave the only copy on the same cluster you are trying to recover.

## Backup Notes

- take backups only from a healthy cluster
- verify `etcdutl snapshot status` succeeds
- keep multiple dated backups
- store backups outside the cluster

## Restore Preconditions

Before restoring:

1. power off or isolate all old control-plane nodes that might still be running
2. decide which nodes will become the recovered control-plane set
3. use the same etcd snapshot on all restored control-plane nodes

For this stack, that is usually:

- `cp-0` at `10.10.10.21`
- `cp-1` at `10.10.10.22`
- `cp-2` at `10.10.10.23`

Do not attempt restore while stale old etcd members are still alive on the network.

## Restore Overview

On each restored control-plane node:

1. stop kubelet
2. restore `/etc/kubernetes` files from backup
3. remove or move aside the old `/var/lib/etcd`
4. restore the same etcd snapshot with a new 3-node cluster definition
5. start kubelet
6. verify etcd and apiserver health

## Example Restore

The following examples assume:

- VIP: `10.10.10.20`
- `cp-0`: `10.10.10.21`
- `cp-1`: `10.10.10.22`
- `cp-2`: `10.10.10.23`

### Step 1: Copy Backup Files To Each Recovery Node

Copy these files to each target control-plane node:

- `snapshot.db`
- `k8s-control-plane-files.tgz`

### Step 2: Restore cp-0

Run on `cp-0`:

```bash
sudo systemctl stop kubelet

sudo tar -C / -xzf k8s-control-plane-files.tgz

sudo mv /var/lib/etcd /var/lib/etcd.old.$(date +%s) 2>/dev/null || true

sudo etcdutl snapshot restore snapshot.db \
  --name cp-0 \
  --initial-cluster cp-0=https://10.10.10.21:2380,cp-1=https://10.10.10.22:2380,cp-2=https://10.10.10.23:2380 \
  --initial-cluster-token etcd-cluster-restore-1 \
  --initial-advertise-peer-urls https://10.10.10.21:2380 \
  --data-dir /var/lib/etcd

sudo systemctl start kubelet
```

### Step 3: Restore cp-1

Run on `cp-1`:

```bash
sudo systemctl stop kubelet

sudo tar -C / -xzf k8s-control-plane-files.tgz

sudo mv /var/lib/etcd /var/lib/etcd.old.$(date +%s) 2>/dev/null || true

sudo etcdutl snapshot restore snapshot.db \
  --name cp-1 \
  --initial-cluster cp-0=https://10.10.10.21:2380,cp-1=https://10.10.10.22:2380,cp-2=https://10.10.10.23:2380 \
  --initial-cluster-token etcd-cluster-restore-1 \
  --initial-advertise-peer-urls https://10.10.10.22:2380 \
  --data-dir /var/lib/etcd

sudo systemctl start kubelet
```

### Step 4: Restore cp-2

Run on `cp-2`:

```bash
sudo systemctl stop kubelet

sudo tar -C / -xzf k8s-control-plane-files.tgz

sudo mv /var/lib/etcd /var/lib/etcd.old.$(date +%s) 2>/dev/null || true

sudo etcdutl snapshot restore snapshot.db \
  --name cp-2 \
  --initial-cluster cp-0=https://10.10.10.21:2380,cp-1=https://10.10.10.22:2380,cp-2=https://10.10.10.23:2380 \
  --initial-cluster-token etcd-cluster-restore-1 \
  --initial-advertise-peer-urls https://10.10.10.23:2380 \
  --data-dir /var/lib/etcd

sudo systemctl start kubelet
```

## Post-Restore Validation

From one restored control-plane node:

```bash
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl get nodes -o wide
kubectl get pods -n kube-system -o wide
```

Check etcd membership:

```bash
ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n kube-system "$ETCD_POD" -- etcdctl \
  --cert=/etc/kubernetes/pki/etcd/peer.crt \
  --key=/etc/kubernetes/pki/etcd/peer.key \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  member list
```

Check API VIP:

```bash
ip addr | grep 10.10.10.20
crictl ps | grep kube-vip
```

If Flannel or other add-ons are missing after restore, reapply them after the control plane is stable.

## Important Caveats

- this is not the normal node replacement path
- this is disaster recovery after quorum loss
- you must restore the same snapshot onto all members
- old broken control-plane nodes must not still be running
- do not mix restored etcd state with live old members

## Recommended Operational Model

- when quorum still exists: use `replace-control-plane.sh`
- when quorum is lost: use this manual backup/restore process

