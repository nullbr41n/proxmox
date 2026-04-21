# 05 Argo CD

Installs Argo CD via Helm after ingress is available.

## Usage

```bash

cd 05-argocd
terraform init
terraform apply
```

Run this after `04-ingress-nginx`.

By default, the Argo CD server Service is `ClusterIP` so it can be exposed through ingress instead of consuming a dedicated MetalLB IP.
The default ingress hostname is `argocd.intra.nixbin.com`.
This stage also registers the Git repository Argo CD should use for the app-of-apps.
For SSH repositories, provide the private key through `TF_VAR_argocd_apps_repo_ssh_private_key`.
