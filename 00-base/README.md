# 00 Base

Single-Proxmox base stage for the simplified Kubernetes stack.

This stage only handles Proxmox connectivity and the shared cloud image download.
It keeps the "common artifact" part separate so later stages can reuse the image ID
without each stage downloading the same file again.

## What It Creates

- A cloud image file on the Proxmox datastore

## What It Does Not Create

- No VMs
- No snippets
- No Kubernetes resources

## Usage

```bash
cd 00-base
source .env #Find this in vault its not commited
terraform init
terraform apply
```

## Outputs

- `cloud_image_file_id`: Use this from later stages

## Notes

- The Proxmox provider still needs SSH access for some node-level operations in later stages.
- Use a snippets datastore/path that your automation SSH user can write to.
