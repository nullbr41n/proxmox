# 08 Proxmox CSI Manual

Manual test bundle for `sergelogvinov/proxmox-csi-plugin` before wiring it into Argo CD.

This folder does not install anything automatically. It gives you:

- a node topology label script
- a `Secret` template containing the Proxmox config
- Helm values for the CSI chart
- a disposable PVC/Pod smoke test

## Assumptions

- All Kubernetes nodes currently run on the same Proxmox host, so they share one zone.
- You want to test a single `ReadWriteOnce` storage class first.
- You will fill in the Proxmox API and storage values yourself.

## 1. Label Nodes

Edit `node-topology-labels.sh` if needed, then run:

```bash
./08-proxmox-csi-manual/node-topology-labels.sh
```

The defaults use:

- `topology.kubernetes.io/region=proxmox`
- `topology.kubernetes.io/zone=pve01`

## 2. Create the Proxmox Config Secret

Edit [secret-proxmox-config.yaml](/Users/tikejhya/data/nixbin/proxmox-prod/scratch/08-proxmox-csi-manual/secret-proxmox-config.yaml), then apply:

```bash
kubectl apply -f 08-proxmox-csi-manual/secret-proxmox-config.yaml
```

## 3. Install the CSI Driver

Edit [values.yaml](/Users/tikejhya/data/nixbin/proxmox-prod/scratch/08-proxmox-csi-manual/values.yaml) to match your Proxmox storage ID and topology.

Then install:

```bash
helm upgrade --install proxmox-csi-plugin \
  --namespace kube-system \
  --create-namespace \
  -f 08-proxmox-csi-manual/values.yaml \
  oci://ghcr.io/sergelogvinov/charts/proxmox-csi-plugin
```

## 4. Run a Smoke Test

```bash
kubectl apply -f 08-proxmox-csi-manual/test-namespace.yaml
kubectl apply -f 08-proxmox-csi-manual/test-pvc-pod.yaml
```

Check:

```bash
kubectl -n proxmox-csi-test get pod,pvc
kubectl get pv
kubectl get csidriver
kubectl get csistoragecapacities -A
```

Then test restart safety:

```bash
kubectl -n proxmox-csi-test delete pod test-proxmox-csi
kubectl -n proxmox-csi-test get pod -w
```

## 5. Test Backup Copy To `/mnt/backup`

This helper pod mounts the same PVC read-only and the node backup mount via `hostPath`.

```bash
kubectl apply -f 08-proxmox-csi-manual/test-backup-pod.yaml
kubectl -n proxmox-csi-test logs -f pod/test-proxmox-csi-backup
```

It writes into:

```text
/mnt/backup/proxmox-csi-test/<timestamp>
```

Important:

- this is best used when the source PVC is not mounted by another pod
- for live databases, prefer application-aware backups instead of raw filesystem copy

## Notes

- Keep this storage class non-default until you trust it.
- This is intended for `ReadWriteOnce` PVCs, not shared RWX storage.
- Upstream recommends `VirtIO SCSI single` with `iothread` on the VM side for best compatibility/performance.

Sources:

- https://github.com/sergelogvinov/proxmox-csi-plugin
- https://raw.githubusercontent.com/sergelogvinov/proxmox-csi-plugin/main/charts/proxmox-csi-plugin/values.yaml
- https://github.com/sergelogvinov/helm-charts
