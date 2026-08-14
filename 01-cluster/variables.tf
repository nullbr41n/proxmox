variable "proxmox_endpoint" {
  type = string
}

variable "proxmox_token_id" {
  type      = string
  sensitive = true
}

variable "proxmox_token_secret" {
  type      = string
  sensitive = true
}

variable "proxmox_insecure" {
  type    = bool
  default = true
}

variable "proxmox_ssh_user" {
  description = "SSH user for the provider and optional Proxmox-host health checks."
  type        = string
}

variable "proxmox_ssh_node_address" {
  type = string
}

variable "proxmox_ssh_port" {
  type    = number
  default = 22
}

variable "vm_node_name" {
  type = string
}

variable "vm_disk_datastore_id" {
  type = string
}

variable "vm_disk_interface" {
  type    = string
  default = "scsi0"
}

variable "vm_disk_iothread" {
  type    = bool
  default = false
}

variable "vm_disk_discard" {
  type    = string
  default = "ignore"
}

variable "vm_disk_speed_read" {
  description = "Maximum disk read speed in MB/s."
  type        = number
  default     = null

  validation {
    condition     = var.vm_disk_speed_read == null || floor(var.vm_disk_speed_read) == var.vm_disk_speed_read
    error_message = "vm_disk_speed_read must be a whole-number MB/s value."
  }
}

variable "vm_disk_speed_write" {
  description = "Maximum disk write speed in MB/s."
  type        = number
  default     = null

  validation {
    condition     = var.vm_disk_speed_write == null || floor(var.vm_disk_speed_write) == var.vm_disk_speed_write
    error_message = "vm_disk_speed_write must be a whole-number MB/s value."
  }
}

variable "vm_network_device_bridge" {
  type = string
}

variable "vm_network_device_vlan_tag" {
  type    = number
  default = 0
}

variable "vm_ipv4_gateway" {
  type = string
}

variable "vm_resolv_search" {
  type    = string
  default = "local"
}

variable "vm_resolv_nameserver" {
  description = "Upstream DNS server for normal non-cluster name resolution."
  type        = string
}

variable "vm_rocky_password" {
  type      = string
  sensitive = true
}

variable "vm_operating_system_type" {
  type    = string
  default = "l26"
}

variable "vm_initialization_datastore_id" {
  type = string
}

variable "snippet_datastore_id" {
  description = "Snippets datastore. Use a writable non-root path if the SSH user is not root."
  type        = string
}

variable "kubernetes_repo_version" {
  description = "pkgs.k8s.io stable channel to lock (e.g. v1.34 = major.minor). On replace, bootstrap installs the latest patch in this channel. Bump intentionally to move minors (v1.34 → v1.35). Kubernetes major stays 1.x."
  type        = string
  default     = "v1.34"
}

variable "kubeadm_control_plane_hostname" {
  type    = string
  default = "api.server.local"
}

variable "kubeadm_control_plane_vip" {
  description = "API endpoint VIP managed by kube-vip. This must be on the guest Kubernetes subnet, not the Proxmox management subnet."
  type        = string

  validation {
    condition     = join(".", slice(split(".", var.kubeadm_control_plane_vip), 0, 3)) == join(".", slice(split(".", var.vm_ipv4_gateway), 0, 3))
    error_message = "kubeadm_control_plane_vip must be on the same /24 guest subnet as vm_ipv4_gateway. Example: guest nodes 192.168.100.x, VIP 192.168.100.20, gateway 192.168.100.254."
  }
}

variable "kube_vip_interface" {
  type    = string
  default = "eth0"
}

variable "kube_vip_version" {
  description = "kube-vip image tag. v1.0.4+ supports vip_preserve_on_leadership_loss for safer live failover."
  type        = string
  default     = "v1.0.4"
}

variable "kube_vip_lease_duration" {
  description = "kube-vip leader election lease duration in seconds. Increase when the API server is slow to renew leases."
  type        = string
  default     = "30"
}

variable "kube_vip_renew_deadline" {
  description = "kube-vip leader election renew deadline in seconds."
  type        = string
  default     = "15"
}

variable "kube_vip_retry_period" {
  description = "kube-vip leader election retry period in seconds."
  type        = string
  default     = "3"
}

variable "kubeadm_join_port" {
  description = "HTTP port used by the lightweight join server on control-plane nodes."
  type        = number
  default     = 8080
}

variable "kubernetes_topology_region" {
  description = "Node label value for topology.kubernetes.io/region."
  type        = string
  default     = "proxmox"
}

variable "kubernetes_topology_zone" {
  description = "Node label value for topology.kubernetes.io/zone."
  type        = string
  default     = "bhado"
}

variable "cp0_bootstrap_mode" {
  description = "How cp-0 should behave. Use 'init' for first cluster creation and 'join' when recreating cp-0 into an already healthy control-plane quorum."
  type        = string
  default     = "init"

  validation {
    condition     = contains(["init", "join"], var.cp0_bootstrap_mode)
    error_message = "cp0_bootstrap_mode must be either 'init' or 'join'."
  }
}

variable "control_plane_base_octet" {
  description = "Base last octet. VIP uses this value; cp-N uses VIP + N + 1."
  type        = number
  default     = 20
}

variable "control_plane_slot_limit" {
  description = "Highest supported control-plane slot number, inclusive."
  type        = number
  default     = 4
}

variable "worker_base_octet" {
  description = "worker-0 IP last octet."
  type        = number
  default     = 30
}

variable "worker_slot_limit" {
  description = "Highest supported worker slot number, inclusive."
  type        = number
  default     = 9
}

variable "enabled_control_plane_slots" {
  description = "Enabled control-plane slots. Keep 0,1,2 enabled by default."
  type        = set(number)
  default     = [0, 1, 2]

  validation {
    condition     = contains(var.enabled_control_plane_slots, 0)
    error_message = "enabled_control_plane_slots must always include cp-0."
  }
}

variable "enabled_worker_slots" {
  description = "Enabled worker slots."
  type        = set(number)
  default     = [0, 1]
}

variable "control_plane_vm_id_base" {
  description = "VM ID base for cp slots. cp-0 = base, cp-1 = base + 1, etc."
  type        = number
  default     = 101
}

variable "worker_vm_id_base" {
  description = "VM ID base for worker slots. worker-0 = base, worker-1 = base + 1, etc."
  type        = number
  default     = 201
}

variable "control_plane_disk_size" {
  type    = number
  default = 30
}

variable "control_plane_memory_dedicated" {
  type    = number
  default = 4096
}

variable "control_plane_cpu_cores" {
  type    = number
  default = 2
}

variable "worker_disk_size" {
  type    = number
  default = 40
}

variable "worker_memory_dedicated" {
  type    = number
  default = 4096
}

variable "worker_cpu_cores" {
  type    = number
  default = 2
}

variable "wait_via_ssh" {
  description = "Run bootstrap readiness checks through the Proxmox host."
  type        = bool
  default     = true
}

variable "bootstrap_ready_timeout_seconds" {
  description = "Time to wait for cp-0 API readiness."
  type        = number
  default     = 2700
}

variable "backup_nfs_enabled" {
  description = "Mount the shared backup NFS export on every node during first boot."
  type        = bool
  default     = true
}

variable "backup_nfs_server" {
  description = "NFS server hosting the shared backup export."
  type        = string
  default     = "10.10.10.206"
}

variable "backup_nfs_export_path" {
  description = "Export path on the NFS server."
  type        = string
  default     = "/data/backups"
}

variable "backup_nfs_mount_path" {
  description = "Local mountpoint for the shared backup export."
  type        = string
  default     = "/mnt/backup"
}

variable "backup_nfs_mount_options" {
  description = "Mount options used for the shared backup NFS export."
  type        = string
  default     = "rw,vers=4.2,rsize=262144,wsize=262144,hard,proto=tcp,timeo=600,retrans=2,sec=sys,_netdev,nofail,x-systemd.automount,x-systemd.mount-timeout=30"
}

variable "cluster_backup_enabled" {
  description = "Install a systemd timer on control-plane nodes that snapshots etcd and archives PKI/manifests to the backup NFS mount."
  type        = bool
  default     = true
}

variable "cluster_backup_name" {
  description = "Site/color subdirectory under k8s/cluster/ on the backup mount (e.g. khet, bhado)."
  type        = string
  default     = ""
}

variable "cluster_backup_on_calendar" {
  description = "systemd OnCalendar expression for control-plane backups."
  type        = string
  default     = "*-*-* 03:15:00"
}

variable "cluster_backup_keep_daily" {
  description = "Number of daily control-plane backup directories to retain."
  type        = number
  default     = 7
}

variable "cluster_backup_keep_weekly" {
  description = "Number of weekly control-plane backup directories to retain."
  type        = number
  default     = 4
}
