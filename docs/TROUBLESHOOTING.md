# Troubleshooting

## api.server.local: connection refused on port 6443 (after adding join nodes)

### Likely causes

1. **cp-0 /etc/hosts** — cp-0 may still have `api.server.local -> 127.0.0.1` from bootstrap; with multiple nodes the VIP can move to another node
2. **kube-vip leader election** — VIP may have moved to a node whose API server isn't ready yet
3. **kube-vip not running** — DaemonSet pods may have crashed

### Diagnostics

```bash
# From any control-plane node
kubectl get pods -n kube-system -l name=kube-vip-ds
ip addr | grep 192.168.100.20   # VIP - which node has it?
curl -sk https://192.168.100.20:6443/healthz   # Replace with your VIP
cat /etc/hosts | grep api.server.local
```

### Fix (run on cp-0 if api.server.local points to 127.0.0.1)

```bash
VIP="192.168.100.20"   # Your kubeadm_control_plane_ip
sed -i '/api.server.local/d' /etc/hosts
echo "$VIP api.server.local" >> /etc/hosts
systemctl restart kubelet
```

### From your laptop

Ensure `/etc/hosts` has: `192.168.100.20 api.server.local` (use your VIP).

---

## kubectl: "couldn't get current server API group list" / "the server could not find the requested resource"

### Likely causes

1. **kubectl / API server version skew** — Client and server versions differ
2. **cp-0 unreachable** — kubeconfig points to cp-0 (10.100.100.150:6443); if cp-0 is down, kubectl fails
3. **KUBECONFIG not set** — Shell may not have loaded `/etc/profile.d/kubeconfig.sh`

### Diagnostics (run on cp-1 or cp-0)

```bash
# 1. Check versions
kubectl version
kubelet --version

# 2. Verify API server reachability (from cp-1)
curl -sk https://10.100.100.150:6443/healthz

# 3. Force KUBECONFIG
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl get nodes

# 4. Or run as root (has admin.conf)
sudo kubectl get nodes

# 5. Check kubeconfig server
grep server ~/.kube/config
# Should show: server: https://10.100.100.150:6443
```

### Fixes

- **Version skew**: Use the same `kubernetes_repo_version` for init and join. If issues persist, try `v1.31` or `v1.32` in terraform.tfvars and redeploy.
- **cp-0 down**: Ensure cp-0 is running and the API server is up. From cp-0: `systemctl status kubelet`.
- **New shell**: Run `source /etc/profile.d/kubeconfig.sh` or log out and back in so KUBECONFIG is set.

---

## Nodes stuck in NotReady (e.g. only cp-2 Ready, others NotReady)

### Interpreting node conditions

If `kubectl describe node` shows **NodeStatusUnknown** / **"Kubelet stopped posting node status"** — kubelet on that node stopped sending heartbeats to the API server. Flannel can still show `FlannelIsUp`; the problem is kubelet, not CNI.

### Root cause (why nodes end up NotReady)

**DNS returns the first healthy control-plane IP** (e.g. 192.168.100.22). During `kubeadm join`, kubeadm resolves `api.server.local` and writes that IP into the kubelet config. Later, when that node becomes unhealthy or the VIP moves, kubelet still tries the old IP → Connection refused → NodeStatusUnknown.

**Fix (applied in cloud-init)**: `do-join.py` now patches kubelet configs after join to use `api.server.local` instead of the resolved IP, so kubelet re-resolves on each connection. For existing broken nodes: reset and re-join.

### Likely causes

1. **kubelet uses wrong API server** — kubelet config points to a node IP (e.g. `192.168.100.22`) instead of the VIP or `api.server.local`. When the VIP moves or that node goes down, that IP no longer serves the API → Connection refused. Check `journalctl -u kubelet` for `Get "https://192.168.100.22:6443/..."` errors.
2. **kubelet crashed or stopped** — Process died or was killed
3. **kubelet can't reach API server** — DNS (`api.server.local`), network partition, or VIP unreachable
4. **CNI (Flannel) not ready** — Flannel DaemonSet pods failing on some nodes (Flannel uses `kube-flannel` namespace)
5. **containerd/crictl** — Container runtime issues on specific nodes

### Diagnostics (run from a Ready node, e.g. cp-2)

```bash
# 1. Node conditions (look for NodeStatusUnknown / "Kubelet stopped posting node status")
kubectl describe nodes cp-0 cp-1 cp-3 cp-4 | grep -A10 "Conditions:"

# 2. Flannel pods (namespace is kube-flannel, not kube-system)
kubectl get pods -n kube-flannel -l app=flannel -o wide

# 3. Which node has the VIP? (API server runs there)
ip addr | grep 192.168.100.20   # Run on each cp node
```

### Per-node checks (SSH to each NotReady node when you see "Kubelet stopped posting node status")

```bash
# On cp-0, cp-1, cp-3, cp-4 (one at a time)
systemctl status kubelet
journalctl -u kubelet -n 50 --no-pager

# Can this node reach the API?
curl -sk https://api.server.local:6443/healthz
cat /etc/resolv.conf   # Should have nameserver 192.168.100.20 (dns-cp) or your VIP

# Is containerd running?
systemctl status containerd
crictl ps 2>/dev/null || echo "crictl failed"
```

### Fixes

- **kubelet uses node IP instead of VIP** (Connection refused to e.g. `192.168.100.22:6443`): kubelet's config has a concrete node IP. Update it to use the VIP or hostname. On each affected node:

  ```bash
  # 1. Find where kubelet gets its API server URL
  systemctl cat kubelet | grep -E "kubeconfig|bootstrap"
  ls -la /etc/kubernetes/ /var/lib/kubelet/ 2>/dev/null

  # Common paths: /etc/kubernetes/kubelet.conf, /etc/kubernetes/bootstrap-kubelet.conf,
  # or /var/lib/kubelet/kubeconfig. Check which exist and contain "server:"
  grep -r "server:" /etc/kubernetes/ /var/lib/kubelet/ 2>/dev/null

  # 2. Fix each kubeconfig that has the wrong IP (replace paths if yours differ)
  for f in /etc/kubernetes/kubelet.conf /etc/kubernetes/bootstrap-kubelet.conf /var/lib/kubelet/kubeconfig; do
    [ -f "$f" ] && sed -i 's|https://[0-9.]*:6443|https://api.server.local:6443|g' "$f" && echo "Fixed $f"
  done

  # Or use VIP directly: sed -i 's|https://[0-9.]*:6443|https://192.168.100.20:6443|g' /path/to/config

  systemctl restart kubelet
  ```

- **kubelet not running**: `sudo systemctl start kubelet && sudo systemctl enable kubelet`
- **api.server.local unreachable**: Ensure `/etc/resolv.conf` has `nameserver 192.168.100.20` (dns-cp) so `api.server.local` resolves to the VIP. If using `/etc/hosts`, add `192.168.100.20 api.server.local`.
- **Flannel image pull failure**: Check `kubectl describe pod -n kube-flannel -l app=flannel` for ImagePullBackOff. Ensure nodes can reach the container registry.
- **Last resort**: On the NotReady node, `sudo kubeadm reset -f`, then re-join using `curl -s http://api.server.local:8080/join-cp.txt`.

---

## etcd health / quorum checks (when etcd-cp-1 or a specific pod is down)

### Find a healthy etcd pod

```bash
kubectl get pods -n kube-system -l component=etcd
```

### Run checks using any healthy pod

```bash
ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' | cut -d' ' -f1)
kubectl exec -n kube-system "$ETCD_POD" -- etcdctl \
  --cert=/etc/kubernetes/pki/etcd/peer.crt \
  --key=/etc/kubernetes/pki/etcd/peer.key \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  member list
```

### Add a removed etcd member back (e.g. etcd-cp-1 was removed)

**Recommended: reset and re-join**

1. On the removed node (e.g. cp-1):

   ```bash
   sudo kubeadm reset -f
   ```

2. Re-join as a control-plane node:

   ```bash
   curl -s http://api.server.local:8080/join-cp.txt
   # Run the kubeadm join --control-plane --certificate-key ... command from that output
   ```

**Alternative: manual etcd member add**

```bash
ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n kube-system "$ETCD_POD" -- etcdctl \
  --cert=/etc/kubernetes/pki/etcd/peer.crt \
  --key=/etc/kubernetes/pki/etcd/peer.key \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  member add cp-1 --peer-urls=https://192.168.100.22:2380
```

Replace `cp-1` and `192.168.100.22` with the actual hostname and IP. You still need to run `kubeadm join` on that node afterward.
