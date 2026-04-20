# 03 Argo CD

Configures the MetalLB IP pool and L2 advertisement after the MetalLB chart is installed, then installs Argo CD.

## Usage

```bash
export KUBECONFIG=/path/to/admin.conf

cd 03-argocd
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

Run this after `02-metallb`.
Create the app-of-apps `Application` in `04-argocd-apps`.
