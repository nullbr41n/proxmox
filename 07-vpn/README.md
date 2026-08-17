# 07-vpn — WireGuard (wg-easy) + VPN CoreDNS

Standalone Terraform stage for the khet VPN namespace.

## State (NFS)

Canonical path on the share: `/mnt/backup/k8s/khet/terraform/proxmox/07-vpn/terraform.tfstate`
(NFS `10.10.11.203:/data/backups`). From a laptop outside `10.10.11.0/24`, use the
helper in `infra/semaphore/proxmox-k8s` (SSH rsync mirror via a CP):

```bash
# from nullbrain/proxmox/07-vpn (or any cwd)
../../infra/semaphore/proxmox-k8s/scripts/mount-khet-backup.sh
../../infra/semaphore/proxmox-k8s/scripts/tf plan
```

Single writer only — do not `apply` from two machines at once.

## Secrets

`wg_easy_password_hash` is **not** in `terraform.tfvars`. Put it in the repo-root `.env`:

```bash
cd ..   # nullbrain/proxmox
source .env   # must export TF_VAR_wg_easy_password_hash='…' (single-quoted bcrypt)

cd 07-vpn
# ensure /mnt/backup is mounted (see above)
terraform plan
terraform apply
```

Generate a hash:

```bash
docker run --rm ghcr.io/wg-easy/wg-easy:14 wgpw 'YOUR_PASSWORD'
```

Non-secret topology stays in (gitignored) `terraform.tfvars`: MetalLB IPs, public endpoint, allowed IPs, NPM domains.
