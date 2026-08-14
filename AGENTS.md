# Agents — proxmox (bhado)

## Upgrades (hard rule)

**Never** patch live nodes with `dnf update`.

| On every replace | Intentional |
|------------------|-------------|
| Latest Rocky/OS | Bump `kubernetes_repo_version` to move kube minors |
| Latest kube patch in that channel | Kubernetes major stays 1.x; stable only |

1. Refresh `00-base`
2. CP: `01-cluster/scripts/replace-control-plane.sh <cp-N>`
3. Workers: new slot → apply → drain/delete old → remove slot → apply

Cursor rule: `.cursor/rules/immutable-node-upgrades.mdc`

## Container images (hard rule)

**Never** import/load images onto nodes. Ship only via **GHCR** → GitOps pin → cluster pull. Auth: `~/.GITHUB_TOKEN` (`write:packages` + `repo`); if push fails, ask the user — do not sideload.

Cursor rule: `.cursor/rules/ghcr-immutable-images.mdc`
