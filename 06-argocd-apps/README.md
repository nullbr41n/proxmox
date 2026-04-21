# 06 Argo CD Apps

Creates the Argo CD app-of-apps `Application` after Argo CD is already installed.

## Usage

```bash

cd 06-argocd-apps
terraform init
terraform apply
```

Run this after `05-argocd`.
This stage creates the root app-of-apps `Application` pointing at the `argocd` path in your Git repo.
