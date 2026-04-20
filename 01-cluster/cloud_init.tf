locals {
  cp_join_nodes = {
    for slot in local.cp_slots :
    "cp-${slot}" => {
      slot = slot
      ip   = cidrhost(local.cluster_subnet, var.control_plane_base_octet + slot + 1)
    }
    if slot != 0
  }

  cloud_header_base = <<-EOT
#cloud-config
users:
  - name: rocky
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
chpasswd:
  list:
    - "root:${var.vm_rocky_password}"
    - "rocky:${var.vm_rocky_password}"
  expire: False
ssh_pwauth: true

write_files:
  - path: /etc/hosts
    content: |
      127.0.0.1 localhost
      ${var.kubeadm_control_plane_vip} ${var.kubeadm_control_plane_hostname}
    permissions: '0644'
  - path: /etc/resolv.conf
    content: |
      search ${var.vm_resolv_search}
      nameserver ${var.vm_resolv_nameserver}
    permissions: '0644'
  - path: /etc/yum.repos.d/kubernetes.repo
    content: |
      [kubernetes]
      name=Kubernetes
      baseurl=https://pkgs.k8s.io/core:/stable:/${var.kubernetes_repo_version}/rpm/
      enabled=1
      gpgcheck=1
      gpgkey=https://pkgs.k8s.io/core:/stable:/${var.kubernetes_repo_version}/rpm/repodata/repomd.xml.key
    permissions: '0644'
  - path: /etc/yum.repos.d/docker-ce.repo
    content: |
      [docker-ce-stable]
      name=Docker CE Stable - $basearch
      baseurl=https://download.docker.com/linux/rhel/$releasever/$basearch/stable
      enabled=1
      gpgcheck=0
    permissions: '0644'
  - path: /etc/profile.d/kubeconfig.sh
    content: |
      if [ -f /etc/kubernetes/super-admin.conf ]; then
        export KUBECONFIG=/etc/kubernetes/super-admin.conf
      elif [ -f /etc/kubernetes/admin.conf ]; then
        export KUBECONFIG=/etc/kubernetes/admin.conf
      fi
    permissions: '0644'
  - path: /usr/local/bin/install-kube-vip.sh
    content: |
      #!/bin/bash
      set -euo pipefail

      IFACE="$1"
      VIP="$2"
      VERSION="$3"
      LOG_FILE="/var/log/install-kube-vip.log"
      MANIFEST_DIR="/etc/kubernetes/manifests"
      MANIFEST_PATH="$${MANIFEST_DIR}/kube-vip.yaml"
      TMP_PATH="$${MANIFEST_PATH}.tmp"
      IMAGE="ghcr.io/kube-vip/kube-vip:$${VERSION}"

      exec >>"$${LOG_FILE}" 2>&1
      echo "[$(date -Iseconds)] install-kube-vip start iface=$${IFACE} vip=$${VIP} version=$${VERSION}"

      mkdir -p "$${MANIFEST_DIR}"
      rm -f "$${TMP_PATH}"

      for i in $(seq 1 5); do
        echo "[$(date -Iseconds)] attempt=$${i} pull image"
        ctr -n k8s.io image pull "$${IMAGE}" && break
        sleep 2
      done

      for i in $(seq 1 5); do
        echo "[$(date -Iseconds)] attempt=$${i} generate manifest"
        if ctr -n k8s.io run --rm --net-host "$${IMAGE}" kube-vip /kube-vip manifest pod \
          --interface "$${IFACE}" \
          --address "$${VIP}" \
          --controlplane \
          --arp \
          --leaderElection > "$${TMP_PATH}"; then
          break
        fi
        sleep 2
      done

      test -s "$${TMP_PATH}"

      if [ -f /etc/kubernetes/super-admin.conf ]; then
        echo "[$(date -Iseconds)] using super-admin.conf for kube-vip"
        sed -i 's|path: /etc/kubernetes/admin.conf|path: /etc/kubernetes/super-admin.conf|' "$${TMP_PATH}"
      fi

      mv "$${TMP_PATH}" "$${MANIFEST_PATH}"
      echo "[$(date -Iseconds)] install-kube-vip complete"
    permissions: '0700'
  - path: /usr/local/bin/do-control-plane-join.py
    content: |
      #!/usr/bin/env python3
      import glob
      import os
      import re
      import subprocess
      import sys

      advertise_ip = sys.argv[1]
      hostname = sys.argv[2]
      join_file = sys.argv[3] if len(sys.argv) > 3 else "/tmp/join-cp.txt"

      with open(join_file, encoding="utf-8") as fh:
          cmd = fh.read().strip()

      if not cmd.startswith("kubeadm join"):
          raise SystemExit("Invalid join-cp.txt")

      cmd += f" --apiserver-advertise-address={advertise_ip} --ignore-preflight-errors=all"
      subprocess.run(cmd.split(), check=True)

      for path in glob.glob("/etc/kubernetes/*.conf") + glob.glob("/var/lib/kubelet/*"):
          if not os.path.isfile(path):
              continue
          with open(path, encoding="utf-8") as fh:
              data = fh.read()
          new_data = re.sub(
              r'https://\d+\.\d+\.\d+\.\d+:6443',
              f'https://{hostname}:6443',
              data,
          )
          if new_data != data:
              with open(path, "w", encoding="utf-8") as fh:
                  fh.write(new_data)

      subprocess.run(["systemctl", "restart", "kubelet"], check=False)
    permissions: '0700'
  - path: /usr/local/bin/refresh-join-files.py
    content: |
      #!/usr/bin/env python3
      import os
      import re
      import subprocess

      kubeconfig = "/etc/kubernetes/super-admin.conf" if os.path.isfile("/etc/kubernetes/super-admin.conf") else "/etc/kubernetes/admin.conf"
      env = {**os.environ, "KUBECONFIG": kubeconfig}
      join = subprocess.run(
          ["kubeadm", "token", "create", "--print-join-command"],
          capture_output=True,
          text=True,
          env=env,
          timeout=30,
      )
      if join.returncode != 0:
          raise SystemExit(1)
      upload = subprocess.run(
          ["kubeadm", "init", "phase", "upload-certs", "--upload-certs"],
          capture_output=True,
          text=True,
          env=env,
          timeout=60,
      )
      match = re.search(r"[a-f0-9]{64}", upload.stdout + upload.stderr)
      if not match:
          raise SystemExit(1)
      join_cmd = re.sub(
          r'https?://', '',
          join.stdout.strip(),
      )
      join_cmd = re.sub(
          r'\\d+\\.\\d+\\.\\d+\\.\\d+:6443',
          '${var.kubeadm_control_plane_hostname}:6443',
          join_cmd,
      )
      os.makedirs("/root/join-cmd", exist_ok=True)
      with open("/root/join-cmd/join.txt", "w", encoding="utf-8") as fh:
          fh.write(join_cmd + "\n")
      with open("/root/join-cmd/join-cp.txt", "w", encoding="utf-8") as fh:
          fh.write(join_cmd + " --control-plane --certificate-key " + match.group(0) + "\n")
    permissions: '0700'
  - path: /usr/local/bin/cleanup-etcd.py
    content: |
      #!/usr/bin/env python3
      import os
      import re
      import subprocess
      import sys

      kubeconfig = "/etc/kubernetes/super-admin.conf" if os.path.isfile("/etc/kubernetes/super-admin.conf") else "/etc/kubernetes/admin.conf"
      env = {**os.environ, "KUBECONFIG": kubeconfig}
      hostname = open("/etc/hostname", encoding="utf-8").read().strip()
      target_name = sys.argv[1] if len(sys.argv) > 1 else None
      target_ip = sys.argv[2] if len(sys.argv) > 2 else None
      etcd = [
          "kubectl", "exec", "-n", "kube-system", f"etcd-{hostname}", "--",
          "etcdctl",
          "--cert=/etc/kubernetes/pki/etcd/peer.crt",
          "--key=/etc/kubernetes/pki/etcd/peer.key",
          "--cacert=/etc/kubernetes/pki/etcd/ca.crt",
      ]
      result = subprocess.run(etcd + ["member", "list"], capture_output=True, text=True, env=env, timeout=20)
      if result.returncode != 0:
          raise SystemExit(0)
      members = []
      for line in result.stdout.splitlines():
          parts = [part.strip() for part in line.split(",")]
          if len(parts) < 5:
              continue
          members.append(
              {
                  "id": parts[0],
                  "name": parts[2],
                  "peer": parts[3],
                  "client": parts[4],
              }
          )

      for member in members:
          if target_name is not None or target_ip is not None:
              identity = " ".join([member["name"], member["peer"], member["client"]])
              if target_name and target_name not in identity:
                  continue
              if target_ip and target_ip not in identity:
                  continue
          try:
              probe = subprocess.run(
                  etcd + ["endpoint", "health", f"--endpoints={member['client']}"],
                  capture_output=True,
                  env=env,
                  timeout=5,
              )
              unhealthy = probe.returncode != 0
          except subprocess.TimeoutExpired:
              unhealthy = True
          if unhealthy:
              subprocess.run(etcd + ["member", "remove", member["id"]], capture_output=True, env=env, timeout=20)
    permissions: '0700'
  - path: /usr/local/bin/join-server.py
    content: |
      #!/usr/bin/env python3
      import http.server
      import os
      import urllib.parse
      import subprocess
      import time

      class Handler(http.server.SimpleHTTPRequestHandler):
          def __init__(self, request, client_address, server):
              super().__init__(request, client_address, server, directory="/root/join-cmd")

          def do_GET(self):
              parsed = urllib.parse.urlparse(self.path)
              query = urllib.parse.parse_qs(parsed.query)
              if parsed.path.startswith("/join-cp"):
                  try:
                      cmd = ["/usr/bin/python3", "/usr/local/bin/cleanup-etcd.py"]
                      node = query.get("node", [])
                      ip = query.get("ip", [])
                      if node:
                          cmd.append(node[0])
                      if ip:
                          cmd.append(ip[0])
                      subprocess.run(cmd, timeout=30)
                  except Exception:
                      pass
                  try:
                      subprocess.run(["/usr/bin/python3", "/usr/local/bin/refresh-join-files.py"], timeout=90)
                  except Exception:
                      pass
              if parsed.path.startswith("/join"):
                  try:
                      path = "/root/join-cmd/join-cp.txt" if "join-cp" in parsed.path else "/root/join-cmd/join.txt"
                      age_ok = parsed.path.startswith("/join-cp") or (os.path.isfile(path) and (time.time() - os.path.getmtime(path)) < 3600)
                      if not age_ok:
                          subprocess.run(["/usr/bin/python3", "/usr/local/bin/refresh-join-files.py"], timeout=90)
                  except Exception:
                      pass
              super().do_GET()

      http.server.HTTPServer(("", ${var.kubeadm_join_port}), Handler).serve_forever()
    permissions: '0700'
  - path: /etc/systemd/system/join-server.service
    content: |
      [Unit]
      Description=Serve kubeadm join files
      After=network-online.target kubelet.service
      ConditionPathExistsGlob=/etc/kubernetes/*admin.conf

      [Service]
      Type=simple
      ExecStart=/bin/bash -lc 'if [ -f /etc/kubernetes/super-admin.conf ]; then export KUBECONFIG=/etc/kubernetes/super-admin.conf; else export KUBECONFIG=/etc/kubernetes/admin.conf; fi; exec /usr/bin/python3 /usr/local/bin/join-server.py'
      Restart=on-failure
      RestartSec=5

      [Install]
      WantedBy=multi-user.target
    permissions: '0644'

packages:
  - dnf-plugins-core
  - containerd.io
  - cri-tools
  - jq
  - kubelet
  - kubeadm
  - kubectl

EOT

  bootstrap_runcmd = <<-EOT
runcmd:
  - |
    #!/bin/bash
    set -e
    echo cp-0 > /etc/hostname
    hostname cp-0 || true
    swapoff -a || true
    sed -i '/ swap / s/^/#/' /etc/fstab
    modprobe br_netfilter overlay 2>/dev/null || true
    echo -e 'br_netfilter\noverlay' > /etc/modules-load.d/br_netfilter.conf
    cat >/etc/sysctl.d/99-kubernetes.conf <<'EOF'
    net.bridge.bridge-nf-call-iptables = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.ipv4.ip_forward = 1
    EOF
    sysctl --system
    mkdir -p /etc/containerd /etc/kubernetes/manifests
    containerd config default > /etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    systemctl enable --now containerd
    for i in $(seq 1 30); do crictl info >/dev/null 2>&1 && break; sleep 2; done
    systemctl enable kubelet
    if [ "${var.cp0_bootstrap_mode}" = "join" ]; then
      rm -f /tmp/join-cp.txt
      for peer in ${local.control_plane_peer_ips}; do
        [ "$peer" = "${local.cp0_ip}" ] && continue
        for i in $(seq 1 12); do
          curl -sf "http://$peer:${var.kubeadm_join_port}/join-cp.txt?node=cp-0&ip=${local.cp0_ip}" -o /tmp/join-cp.txt && break 2
          sleep 10
        done
      done
      [ -f /tmp/join-cp.txt ] || { echo "Failed to fetch join-cp.txt for cp-0 join mode"; exit 1; }
      /usr/bin/python3 /usr/local/bin/do-control-plane-join.py ${local.cp0_ip} ${var.kubeadm_control_plane_hostname} /tmp/join-cp.txt
    else
      sed -i '/ ${var.kubeadm_control_plane_hostname}$/d' /etc/hosts
      echo "${local.cp0_ip} ${var.kubeadm_control_plane_hostname}" >> /etc/hosts
      kubeadm init --control-plane-endpoint=${var.kubeadm_control_plane_hostname}:6443 --apiserver-advertise-address=${local.cp0_ip} --pod-network-cidr=10.244.0.0/16 --upload-certs --ignore-preflight-errors=all
    fi
    /usr/local/bin/install-kube-vip.sh ${var.kube_vip_interface} ${var.kubeadm_control_plane_vip} ${var.kube_vip_version}
    test -s /etc/kubernetes/manifests/kube-vip.yaml
    mkdir -p /root/.kube /home/rocky/.kube
    if [ -f /etc/kubernetes/super-admin.conf ]; then cp -f /etc/kubernetes/super-admin.conf /root/.kube/config; else cp -f /etc/kubernetes/admin.conf /root/.kube/config; fi
    if [ -f /etc/kubernetes/super-admin.conf ]; then cp -f /etc/kubernetes/super-admin.conf /home/rocky/.kube/config; else cp -f /etc/kubernetes/admin.conf /home/rocky/.kube/config; fi
    chown -R root:root /root/.kube
    chown -R rocky:rocky /home/rocky/.kube
    if [ -f /etc/kubernetes/super-admin.conf ]; then KCFG=/etc/kubernetes/super-admin.conf; else KCFG=/etc/kubernetes/admin.conf; fi
    export KUBECONFIG=$KCFG
    mkdir -p /root/join-cmd
    for i in $(seq 1 30); do curl -skf https://${var.kubeadm_control_plane_vip}:6443/healthz >/dev/null 2>&1 && break; sleep 2; done
    sed -i '/ ${var.kubeadm_control_plane_hostname}$/d' /etc/hosts
    echo "${var.kubeadm_control_plane_vip} ${var.kubeadm_control_plane_hostname}" >> /etc/hosts
    /usr/bin/python3 /usr/local/bin/refresh-join-files.py
    systemctl daemon-reload
    systemctl enable --now join-server.service
    until kubectl --kubeconfig=$KCFG apply --validate=false -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml; do sleep 15; done
EOT

  control_plane_join_runcmd = {
    for name, cfg in local.cp_join_nodes :
    name => <<-EOT
runcmd:
  - |
    #!/bin/bash
    set -e
    echo ${name} > /etc/hostname
    hostname ${name} || true
    swapoff -a || true
    sed -i '/ swap / s/^/#/' /etc/fstab
    modprobe br_netfilter overlay 2>/dev/null || true
    echo -e 'br_netfilter\noverlay' > /etc/modules-load.d/br_netfilter.conf
    cat >/etc/sysctl.d/99-kubernetes.conf <<'EOF'
    net.bridge.bridge-nf-call-iptables = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.ipv4.ip_forward = 1
    EOF
    sysctl --system
    mkdir -p /etc/containerd /etc/kubernetes/manifests
    containerd config default > /etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    systemctl enable --now containerd
    for i in $(seq 1 30); do crictl info >/dev/null 2>&1 && break; sleep 2; done
    systemctl enable kubelet
    rm -f /tmp/join-cp.txt
    for peer in ${local.control_plane_peer_ips}; do
      [ "$peer" = "${cfg.ip}" ] && continue
      for i in $(seq 1 12); do
        curl -sf "http://$peer:${var.kubeadm_join_port}/join-cp.txt?node=${name}&ip=${cfg.ip}" -o /tmp/join-cp.txt && break 2
        sleep 10
      done
    done
    [ -f /tmp/join-cp.txt ] || { echo "Failed to fetch join-cp.txt"; exit 1; }
    /usr/bin/python3 /usr/local/bin/do-control-plane-join.py ${cfg.ip} ${var.kubeadm_control_plane_hostname} /tmp/join-cp.txt
    /usr/local/bin/install-kube-vip.sh ${var.kube_vip_interface} ${var.kubeadm_control_plane_vip} ${var.kube_vip_version}
    test -s /etc/kubernetes/manifests/kube-vip.yaml
    mkdir -p /root/.kube /home/rocky/.kube
    if [ -f /etc/kubernetes/super-admin.conf ]; then cp -f /etc/kubernetes/super-admin.conf /root/.kube/config; else cp -f /etc/kubernetes/admin.conf /root/.kube/config; fi
    if [ -f /etc/kubernetes/super-admin.conf ]; then cp -f /etc/kubernetes/super-admin.conf /home/rocky/.kube/config; else cp -f /etc/kubernetes/admin.conf /home/rocky/.kube/config; fi
    chown -R root:root /root/.kube
    chown -R rocky:rocky /home/rocky/.kube
    /usr/bin/python3 /usr/local/bin/refresh-join-files.py || true
    systemctl daemon-reload
    systemctl enable --now join-server.service
EOT
  }

  worker_runcmd = {
    for slot in local.worker_slots :
    "worker-${slot}" => <<-EOT
runcmd:
  - |
    #!/bin/bash
    set -e
    echo worker-${slot} > /etc/hostname
    hostname worker-${slot} || true
    swapoff -a || true
    sed -i '/ swap / s/^/#/' /etc/fstab
    modprobe br_netfilter overlay 2>/dev/null || true
    echo -e 'br_netfilter\noverlay' > /etc/modules-load.d/br_netfilter.conf
    cat >/etc/sysctl.d/99-kubernetes.conf <<'EOF'
    net.bridge.bridge-nf-call-iptables = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.ipv4.ip_forward = 1
    EOF
    sysctl --system
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    systemctl enable --now containerd
    for i in $(seq 1 30); do crictl info >/dev/null 2>&1 && break; sleep 2; done
    systemctl enable kubelet
    rm -f /tmp/join.txt
    for peer in ${local.control_plane_peer_ips}; do
      for i in $(seq 1 12); do
        curl -sf "http://$peer:${var.kubeadm_join_port}/join.txt" -o /tmp/join.txt && break 2
        sleep 10
      done
    done
    [ -f /tmp/join.txt ] || { echo "Failed to fetch join.txt"; exit 1; }
    python3 - <<'PY'
    import subprocess

    with open("/tmp/join.txt", encoding="utf-8") as fh:
        cmd = fh.read().strip()
    if not cmd.startswith("kubeadm join"):
        raise SystemExit("Invalid join.txt")
    cmd += " --ignore-preflight-errors=all"
    subprocess.run(cmd.split(), check=True)
    PY
EOT
  }

  cloud_config_cp0 = "${replace(local.cloud_header_base, "#cloud-config\n", "#cloud-config\nhostname: cp-0\n")}${local.bootstrap_runcmd}"

  cloud_config_control_plane = {
    for name, cfg in local.cp_join_nodes :
    name => "${replace(local.cloud_header_base, "#cloud-config\n", "#cloud-config\nhostname: ${name}\n")}${local.control_plane_join_runcmd[name]}"
  }

  cloud_config_worker = {
    for name, script in local.worker_runcmd :
    name => "${replace(local.cloud_header_base, "#cloud-config\n", "#cloud-config\nhostname: ${name}\n")}${script}"
  }
}

resource "proxmox_virtual_environment_file" "cloud_init_cp0" {
  content_type = "snippets"
  datastore_id = var.snippet_datastore_id
  node_name    = var.vm_node_name

  source_raw {
    data      = local.cloud_config_cp0
    file_name = "cloud-init-new-cp-0.cloud-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "cloud_init_control_plane" {
  for_each = local.cloud_config_control_plane

  content_type = "snippets"
  datastore_id = var.snippet_datastore_id
  node_name    = var.vm_node_name

  source_raw {
    data      = each.value
    file_name = "cloud-init-${each.key}.cloud-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "cloud_init_worker" {
  for_each = local.cloud_config_worker

  content_type = "snippets"
  datastore_id = var.snippet_datastore_id
  node_name    = var.vm_node_name

  source_raw {
    data      = each.value
    file_name = "cloud-init-${each.key}.cloud-config.yaml"
  }
}
