# 04 ingress-nginx

Installs the `ingress-nginx` controller via Helm and exposes it through a single
`LoadBalancer` Service so MetalLB can assign one external IP for host-based routing.

## Usage

```bash

cd 04-ingress-nginx
terraform init
terraform apply
```

Run this after `03-networking`.

After apply, create DNS `A` records for your application hostnames pointing at the ingress controller Service `EXTERNAL-IP`.
