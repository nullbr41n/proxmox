# 01 Cluster

Single-Proxmox Kubernetes bootstrap stage using:

- `kube-vip` for the API endpoint
- stacked etcd on the control-plane nodes
- fixed control-plane slots (`cp-0`..`cp-4`)
- fixed worker slots (`worker-0`..`worker-9`)

This stage is intentionally opinionated for a single Proxmox host:

- keep 3 control-plane nodes enabled by default
- add a replacement node first
- remove the bad node in a second apply

## Network Assumption

This stack assumes:

- `proxmox_endpoint` and `proxmox_ssh_node_address` point at the Proxmox management IP
- VM guest IPs, gateway, nameserver, and the Kubernetes API VIP all live on the same guest subnet
- the pod CIDR comes from the CNI overlay and is separate from the VM guest subnet

The guest subnet can still be `10.10.10.x` if that is how your environment is designed.

## What It Creates

- `cp-0` bootstrap node
- optional joining control-plane nodes (`cp-1`..`cp-4`)
- optional worker nodes (`worker-0`..`worker-9`)
- cloud-init snippets for each enabled node
- an NFS backup mount on every node at `/mnt/backup` by default
- a daily control-plane backup timer (etcd snapshot + PKI/manifests) on CP nodes → `/mnt/backup/k8s/cluster/<site>/{daily,weekly}`
- kubelet topology labels on every node at first boot

## cp-0 Mode

`cp-0` is controlled explicitly by `cp0_bootstrap_mode`.

- `init`: use this for first cluster creation
- `join`: use this when recreating `cp-0` into an already healthy cluster with surviving control-plane quorum

`cp-1` and above are always join-only.

## Apply Order

```bash
cd ../00-base
terraform init
terraform apply

cd ../01-cluster
terraform init
terraform apply


cd ../02-metallb
terraform init
terraform apply

cd ../03-networking
terraform init
terraform apply
```

## Replacement Workflow

### Replace a bad control-plane node

Example: `cp-1` is bad.

1. Add a new slot to `enabled_control_plane_slots`, for example add `3`.
2. `terraform apply`
3. Wait for the new node to be `Ready` and etcd quorum to be healthy.
4. Remove the bad slot, for example remove `1`.
5. `terraform apply`

This keeps quorum while the replacement joins.

### Recreate cp-0

If `cp-0` is lost but other control-plane nodes still hold quorum:

1. set `cp0_bootstrap_mode = "join"`
2. recreate `cp-0`
3. let `cp-0` rejoin as a control-plane node

Or use the helper:

```bash
./scripts/replace-control-plane.sh cp-0
```

That wrapper:

- auto-detects a healthy survivor by default
- checks survivor API and join-server access
- refuses obvious quorum-risk replacements unless `--force` is passed
- removes a stale unhealthy etcd member for the target hostname/IP
- forces Terraform to replace the requested control-plane node, using `cp0_bootstrap_mode=join` only when the target is `cp-0`

Here, survivor means a healthy remaining control-plane node that still has working API and join-server access.

You can also use it for `cp-1`..`cp-4`:

```bash
./scripts/replace-control-plane.sh cp-1
```

For first cluster creation, keep:

```hcl
cp0_bootstrap_mode = "init"
```

### Replace a bad worker node

Example: `worker-1` is bad.

1. Add a new worker slot, for example `2`.
2. `terraform apply`
3. Drain/delete the bad worker if it is still reachable.
4. Remove the bad worker slot, for example `1`.
5. `terraform apply`

## Design Notes

- The API endpoint is `api.server.local`, pinned via `/etc/hosts` to the `kube-vip` address.
- Control-plane join nodes fetch `join-cp.txt` from healthy peer IPs.
- Worker nodes fetch `join.txt` from healthy control-plane peer IPs.
- The join server runs on every healthy control-plane node to avoid a hard dependency on `cp-0` after bootstrap.
- A small etcd cleanup script is kept so a dead control-plane member does not permanently block replacement.
- Nodes install `nfs-utils` and configure `${var.backup_nfs_server}:${var.backup_nfs_export_path}` at `${var.backup_nfs_mount_path}` on first boot for backup targets.
- The backup mount is persisted in `/etc/fstab` with `_netdev`, `nofail`, and `x-systemd.automount` so machine reboots do not block on NFS availability.
- Control-plane nodes enable `k8s-control-plane-backup.timer` (daily) which writes etcd `snapshot.db` + `k8s-control-plane-files.tgz` to `${backup_nfs_mount_path}/k8s/cluster/<cluster_backup_name>/{daily,weekly}`. An NFS flock ensures only one CP runs the backup. For already-running nodes use `./scripts/install-control-plane-backup.sh --run-now`.
- Nodes register with `topology.kubernetes.io/region=${var.kubernetes_topology_region}` and `topology.kubernetes.io/zone=${var.kubernetes_topology_zone}` via kubelet startup args on first boot.
- Cloud-init and bootstrap are treated as first-boot initialization. Changing the uploaded cloud-init snippet reference later does not recreate an existing VM.

## Limits

- This is not infrastructure HA. If the single Proxmox host fails, the cluster is down.
- The goal is resilient in-guest Kubernetes behavior and predictable node replacement.
