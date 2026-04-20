# Proxmox management network and guest VM network in this environment: 10.10.10.x
proxmox_endpoint        = "https://10.10.10.1:8006/api2/json"
proxmox_insecure        = true
proxmox_ssh_node_address = "10.10.10.1"
proxmox_ssh_port         = 21736

vm_node_name                   = "bhado"        #nodeName
vm_disk_datastore_id           = "lvm-4tb"    #StorageForDisk (e.g: vm-100-disk-0)
vm_disk_interface              = "scsi0"        #harddisk interface
vm_disk_iothread               = false
vm_disk_discard                = "ignore"
vm_disk_speed_read             = 2
vm_disk_speed_write            = 2
vm_network_device_bridge       = "vmbr1"   # Guest Kubernetes VM network bridge
vm_network_device_vlan_tag     = 0         # Guest Kubernetes VLAN tag, or 0 for untagged
vm_operating_system_type       = "l26"
vm_initialization_datastore_id = "lvm-4tb" #StorageForDisk (e.g: vm-100-disk-0)
snippet_datastore_id           = "snippets"     #SnippetDisk (e.g: Backup, import, ISO, snippet, template)

vm_ipv4_gateway      = "10.10.10.254"
vm_resolv_search     = "local"
vm_resolv_nameserver = "10.10.10.254"

proxmox_ssh_user         = "nixservuser001"

kubernetes_repo_version        = "v1.34"
kubeadm_control_plane_hostname = "api.server.local"
kubeadm_control_plane_vip      = "10.10.10.20"
kube_vip_interface             = "eth0"
kube_vip_version               = "v0.8.0"
kubeadm_join_port              = 8080
cp0_bootstrap_mode             = "init"

control_plane_base_octet       = 20
enabled_control_plane_slots    = [0, 1, 2]

worker_base_octet              = 30
enabled_worker_slots           = [0, 1]

control_plane_vm_id_base       = 101
worker_vm_id_base              = 201
