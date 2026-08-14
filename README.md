# Single-Proxmox Kubernetes Stack

## TL;DR

- First run: apply `00-base`, then apply `01-cluster`.
- Then apply `02-metallb`, `03-networking`, `04-ingress-nginx`, `05-argocd`, then `06-argocd-apps`.
- Everything after a functional Argo CD bootstrap now lives under `projects/`.
- Put secrets in `.env` as `TF_VAR_*`, not in committed `terraform.tfvars`.
- Later runs: do not treat an existing cluster like fresh bootstrap. Replace bad nodes with `01-cluster/scripts/replace-control-plane.sh`.

## Usage

Create `.env` with:

```bash
export TF_VAR_proxmox_token_id="replace-me"
export TF_VAR_proxmox_token_secret="replace-me"
export TF_VAR_vm_rocky_password="replace-me"
export TF_VAR_argocd_apps_repo_ssh_private_key="$(cat ./replace./me")"
export TF_VAR_kubeconfig_path="replace-me"
```

Then run:

```bash
source .env

cd 00-base
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

cd ../04-ingress-nginx
terraform init
terraform apply

cd ../05-argocd
terraform init
terraform apply

cd ../06-argocd-apps
terraform init
terraform apply
```

If this is not the first cluster run, use node replacement instead of fresh bootstrap:

```bash
cd 01-cluster
./scripts/replace-control-plane.sh cp-0
./scripts/replace-control-plane.sh cp-1
```

**Hard rule:** do not `dnf update` live nodes. OS/package currency = refresh `00-base` + replace (see `AGENTS.md`, `01-cluster/README.md`).

This is the simplified Kubernetes layout for a single Proxmox host.

It is designed for:

- one Proxmox hypervisor
- three control-plane VMs by default
- worker nodes that can be replaced by adding a new slot first
- `kube-vip` as the stable Kubernetes API endpoint

This is not full infrastructure HA. If the Proxmox host fails, the cluster fails.
The goal is stable cluster behavior while the host is healthy, plus predictable node replacement.

## Networks

This stack assumes:

- the Proxmox API/SSH network is reachable on `10.10.10.x`
- the VM guest network may also be on `10.10.10.x`
- the pod network is separate and comes from the CNI overlay

What matters is this:

- `kubeadm_control_plane_vip` must be on the same guest subnet as the VM NICs
- `vm_ipv4_gateway` and `vm_resolv_nameserver` must match that guest subnet
- the pod network is not the same thing as the VM node network

Example:

```hcl
proxmox_endpoint            = "https://10.10.10.1:8006/api2/json"
proxmox_ssh_node_address    = "10.10.10.1"
vm_ipv4_gateway             = "10.10.10.254"
vm_resolv_nameserver        = "10.10.10.240"
kubeadm_control_plane_vip   = "10.10.10.20"
```

## Layout

```text
                    +--------------------------------------+
                    |          Single Proxmox Host         |
                    |               (pve01)                |
                    |                                      |
                    |  +-------------------------------+   |
kubectl / Terraform |  |         kube-vip VIP          |   |
------ api.server.local --> 10.10.10.20:6443           |   |
                    |  +---------------+---------------+   |
                    |                  |                   |
                    |   +--------------+--------------+    |
                    |   |              |              |    |
                    |   v              v              v    |
                    | +------+      +------+      +------+ |
                    | | cp-0 |      | cp-1 |      | cp-2 | |
                    | |etcd  |      |etcd  |      |etcd  | |
                    | |API   |      |API   |      |API   | |
                    | +--+---+      +--+---+      +--+---+ |
                    |    |             |             |     |
                    |    +------+------+-------------+     |
                    |           stacked etcd quorum        |
                    |                                      |
                    | +----------+     +----------+        |
                    | | worker-0 |     | worker-1 |        |
                    | +----------+     +----------+        |
                    +--------------------------------------+
```

## Terraform Stages

```text
00-base
  |
  |-- download shared cloud image to Proxmox datastore
  v
01-cluster
  |
  |-- create cp-0
  |-- kubeadm init on cp-0
  |-- kube-vip provides stable API VIP
  |-- create cp-1, cp-2, ... sequentially
  |-- create worker-0, worker-1, ...
  v
02-metallb
  |
  |-- install MetalLB via Helm
  v
03-networking
  |
  |-- configure MetalLB IPAddressPool and L2Advertisement
  v
04-ingress-nginx
  |
  |-- install ingress-nginx via Helm
  |-- ingress controller Service receives one MetalLB IP
  v
05-argocd
  |
  |-- install Argo CD via Helm
  v
06-argocd-apps
  |
  |-- create app-of-apps Application
  v
projects/
  |
  |-- app manifests and post-bootstrap workloads managed after Argo CD is up
```

## Control-Plane Flow

```text
1. cp-0 boots
2. cp-0 either init's or joins, based on cp0_bootstrap_mode
3. cp-0 creates kube-vip static pod
4. cp-0 starts join-server
5. cp-1 / cp-2 fetch join-cp.txt and join sequentially
6. each healthy control-plane node can serve join files
7. workers fetch join.txt and join the cluster
```

## cp-0 Mode

`cp-0` is the only slot with an explicit mode switch:

- `cp0_bootstrap_mode = "init"`:
  - use for first cluster creation
  - `cp-0` runs `kubeadm init`

- `cp0_bootstrap_mode = "join"`:
  - use when recreating `cp-0` into an already healthy cluster
  - `cp-0` fetches `join-cp.txt` from peers and runs `kubeadm join --control-plane`

`cp-1` and later slots are always join-only.

## Quorum

In this setup, the control plane uses stacked etcd.

Each control-plane node runs:

- `kube-apiserver`
- `controller-manager`
- `scheduler`
- local `etcd`

For etcd, quorum means:

- more than half of the etcd members must be healthy
- with 3 control-plane nodes, quorum is 2
- with 5 control-plane nodes, quorum is 3

Examples:

- 3 control-plane nodes: `cp-0`, `cp-1`, `cp-2`
  - 3 healthy: OK
  - 2 healthy: quorum still exists
  - 1 healthy: no quorum, control plane is effectively broken

- 5 control-plane nodes: `cp-0`..`cp-4`
  - 3 healthy: quorum still exists
  - 2 healthy: no quorum

For a single Proxmox host, 3 control-plane nodes is the practical default.
It gives good resilience against a broken VM or bad Kubernetes node while avoiding extra complexity.

## Replacement Model

The design uses fixed slots.

Control-plane slots:

- `cp-0`
- `cp-1`
- `cp-2`
- `cp-3`
- `cp-4`

Worker slots:

- `worker-0`
- `worker-1`
- ...
- `worker-9`

The intended pattern is:

1. add a new slot
2. apply Terraform
3. wait for the new node to become `Ready`
4. remove the bad slot
5. apply Terraform again

This avoids deleting capacity before replacement capacity exists.

Cloud-init and bootstrap are first-boot only in this stack. Updating the uploaded cloud-init snippet reference later does not recreate an existing VM.

## How A New Control-Plane Node Joins

Example: `cp-1` is unhealthy and you want `cp-3` to replace it.

Current state:

```hcl
enabled_control_plane_slots = [0, 1, 2]
cp0_bootstrap_mode          = "init"
```

Step 1: add replacement slot

```hcl
enabled_control_plane_slots = [0, 1, 2, 3]
```

Apply:

```bash
cd 01-cluster
terraform apply
```

What happens:

1. Terraform creates `cp-3`
2. `cp-3` boots with cloud-init
3. `cp-3` starts containerd and kubelet
4. `cp-3` creates its `kube-vip` static pod
5. `cp-3` fetches `join-cp.txt` from a healthy existing control-plane node
6. `cp-3` runs `kubeadm join --control-plane`
7. `cp-3` joins etcd and the Kubernetes control plane

After `cp-3` is healthy and etcd quorum is fine, remove the bad slot:

```hcl
enabled_control_plane_slots = [0, 2, 3]
```

Then apply again:

```bash
terraform apply
```

That destroys `cp-1` after replacement is already present.

## How To Recreate cp-0

If `cp-0` is lost but `cp-1` and `cp-2` still keep quorum:

```hcl
enabled_control_plane_slots = [0, 1, 2]
cp0_bootstrap_mode          = "join"
```

Then recreate `cp-0`.

Recommended:

```bash
cd 01-cluster
./scripts/replace-control-plane.sh cp-0
```

In that mode, `cp-0` will:

1. fetch `join-cp.txt` from healthy peers
2. run `kubeadm join --control-plane`
3. install `kube-vip`
4. refresh join files and serve them again

The same helper can be used for any control-plane slot:

```bash
cd 01-cluster
./scripts/replace-control-plane.sh cp-1
```

The helper also verifies survivor health and removes a stale unhealthy etcd member for the target hostname/IP before the Terraform replacement runs.

## How A New Worker Node Joins

Example: `worker-1` is bad and `worker-2` will replace it.

Current state:

```hcl
enabled_worker_slots = [0, 1]
```

Step 1: add replacement slot

```hcl
enabled_worker_slots = [0, 1, 2]
```

Apply:

```bash
cd 01-cluster
terraform apply
```

What happens:

1. Terraform creates `worker-2`
2. `worker-2` boots
3. it fetches `join.txt` from a healthy control-plane node
4. it runs `kubeadm join`
5. it becomes a normal schedulable worker

If `worker-1` is still reachable, drain it first:

```bash
kubectl drain worker-1 --ignore-daemonsets --delete-emptydir-data
kubectl delete node worker-1
```

Then remove the bad slot:

```hcl
enabled_worker_slots = [0, 2]
```

Apply again:

```bash
terraform apply
```

## Getting Started

1. Prepare `00-base`:

```bash
cd 00-base
cp terraform.tfvars.example terraform.tfvars
```

2. Edit `terraform.tfvars` and set:

- Proxmox API endpoint
- API token
- SSH user
- Proxmox node name/address
- cloud image URL/datastore

3. Apply base:

```bash
terraform init
terraform apply
```

4. Prepare `01-cluster`:

```bash
cd ../01-cluster
cp terraform.tfvars.example terraform.tfvars
```

5. Edit `terraform.tfvars` and set:

- Proxmox API/token/SSH settings
- VM storage/network settings
- writable `snippet_datastore_id`
- `kubeadm_control_plane_vip`
- `kube_vip_interface`
- initial enabled control-plane and worker slots

6. Apply cluster bootstrap:

```bash
terraform init
terraform apply
```

## Recommended Initial Values

For a single Proxmox host:

```hcl
enabled_control_plane_slots = [0, 1, 2]
enabled_worker_slots        = [0, 1]
```

That gives:

- 3 control-plane nodes
- quorum of 2
- 2 worker nodes

## Operational Checks

After bootstrap:

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get pods -n kube-system
```

Check etcd and control-plane health:

```bash
kubectl get pods -n kube-system -l component=etcd
kubectl get --raw='/readyz?verbose'
kubectl get --raw='/healthz'
```

Check which node currently holds the VIP:

```bash
kubectl get nodes
```

Then SSH to control-plane nodes and inspect:

```bash
ip addr | grep 10.10.10.20
```

## Important Limits

- one Proxmox host is still one hard failure domain
- local storage is not HA storage
- this design improves Kubernetes node replacement, not hypervisor failure tolerance
- backups and etcd snapshots still matter
