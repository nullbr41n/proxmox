# 02 MetalLB

Installs MetalLB via Helm only.

## Usage

```bash

cd 02-metallb
terraform init
terraform apply
```

Run this after `01-cluster`.
Configure the MetalLB IP pool and L2 advertisement in `03-networking`.
