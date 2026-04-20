# 04 Argo CD Apps

Creates the Argo CD app-of-apps `Application` after Argo CD is already installed.

## Usage

```bash
export KUBECONFIG=/path/to/admin.conf

cd 04-argocd-apps
terraform init
terraform apply
```

Run this after `03-argocd`.
