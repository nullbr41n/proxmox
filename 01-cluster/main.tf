locals {
  cp_slots     = toset([for slot in var.enabled_control_plane_slots : slot if slot >= 0 && slot <= var.control_plane_slot_limit])
  worker_slots = toset([for slot in var.enabled_worker_slots : slot if slot >= 0 && slot <= var.worker_slot_limit])

  vip_parts      = split(".", var.kubeadm_control_plane_vip)
  cluster_subnet = "${join(".", slice(local.vip_parts, 0, 3))}.0/24"

  cp0_ip = cidrhost(local.cluster_subnet, var.control_plane_base_octet + 1)
  cp1_ip = cidrhost(local.cluster_subnet, var.control_plane_base_octet + 2)
  cp2_ip = cidrhost(local.cluster_subnet, var.control_plane_base_octet + 3)
  cp3_ip = cidrhost(local.cluster_subnet, var.control_plane_base_octet + 4)
  cp4_ip = cidrhost(local.cluster_subnet, var.control_plane_base_octet + 5)

  control_plane_peer_ips = join(" ", [local.cp0_ip, local.cp1_ip, local.cp2_ip, local.cp3_ip, local.cp4_ip])

  worker_map = {
    for slot in local.worker_slots :
    "worker-${slot}" => {
      name                = "worker-${slot}"
      vm_id               = var.worker_vm_id_base + slot
      disk_size           = var.worker_disk_size
      disk_import_file_id = data.terraform_remote_state.base.outputs.cloud_image_file_id
      memory_dedicated    = var.worker_memory_dedicated
      cpu_cores           = var.worker_cpu_cores
      tags                = ["k8s", "worker"]
      initialization = {
        user_data_file_id = proxmox_virtual_environment_file.cloud_init_worker["worker-${slot}"].id
        ipv4_address      = "${cidrhost(local.cluster_subnet, var.worker_base_octet + slot)}/24"
        ipv4_gateway      = var.vm_ipv4_gateway
        username          = "rocky"
        password          = var.vm_rocky_password
        ssh_keys          = []
      }
    }
  }
}

module "control_plane_bootstrap" {
  count  = contains(local.cp_slots, 0) ? 1 : 0
  source = "../modules/vm"

  node_name                   = var.vm_node_name
  disk_datastore_id           = var.vm_disk_datastore_id
  disk_interface              = var.vm_disk_interface
  disk_iothread               = var.vm_disk_iothread
  disk_discard                = var.vm_disk_discard
  disk_speed_read             = var.vm_disk_speed_read
  disk_speed_write            = var.vm_disk_speed_write
  network_device_bridge       = var.vm_network_device_bridge
  network_device_vlan_tag     = var.vm_network_device_vlan_tag
  operating_system_type       = var.vm_operating_system_type
  initialization_datastore_id = var.vm_initialization_datastore_id

  vms = {
    "cp-0" = {
      name                = "cp-0"
      vm_id               = var.control_plane_vm_id_base
      disk_size           = var.control_plane_disk_size
      disk_import_file_id = data.terraform_remote_state.base.outputs.cloud_image_file_id
      memory_dedicated    = var.control_plane_memory_dedicated
      cpu_cores           = var.control_plane_cpu_cores
      tags                = ["k8s", "control-plane", "bootstrap"]
      initialization = {
        user_data_file_id = proxmox_virtual_environment_file.cloud_init_cp0.id
        ipv4_address      = "${local.cp0_ip}/24"
        ipv4_gateway      = var.vm_ipv4_gateway
        username          = "rocky"
        password          = var.vm_rocky_password
        ssh_keys          = []
      }
    }
  }
}

resource "null_resource" "wait_for_cp0" {
  depends_on = [module.control_plane_bootstrap]

  triggers = {
    cp0_ip    = local.cp0_ip
    ssh_mode  = tostring(var.wait_via_ssh)
    timeout_s = tostring(var.bootstrap_ready_timeout_seconds)
  }

  provisioner "local-exec" {
    command = var.wait_via_ssh ? "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p ${var.proxmox_ssh_port} ${var.proxmox_ssh_user}@${var.proxmox_ssh_node_address} '${replace("CP0=\"${local.cp0_ip}\"; for i in $(seq 1 ${var.bootstrap_ready_timeout_seconds / 10}); do curl -skf \"https://$${CP0}:6443/healthz\" 2>/dev/null | grep -q \"ok\" && { echo cp-0 ready; exit 0; }; sleep 10; done; echo Timeout; exit 1", "'", "'\\''")}'" : <<-EOT
      CP0="${local.cp0_ip}"
      for i in $(seq 1 ${var.bootstrap_ready_timeout_seconds / 10}); do
        curl -skf "https://${local.cp0_ip}:6443/healthz" 2>/dev/null | grep -q "ok" && { echo "cp-0 ready"; exit 0; }
        sleep 10
      done
      echo "Timeout waiting for cp-0"
      exit 1
    EOT
  }
}

module "control_plane_join_1" {
  count      = contains(local.cp_slots, 1) ? 1 : 0
  source     = "../modules/vm"
  depends_on = [module.control_plane_bootstrap, null_resource.wait_for_cp0]

  node_name                   = var.vm_node_name
  disk_datastore_id           = var.vm_disk_datastore_id
  disk_interface              = var.vm_disk_interface
  disk_iothread               = var.vm_disk_iothread
  disk_discard                = var.vm_disk_discard
  disk_speed_read             = var.vm_disk_speed_read
  disk_speed_write            = var.vm_disk_speed_write
  network_device_bridge       = var.vm_network_device_bridge
  network_device_vlan_tag     = var.vm_network_device_vlan_tag
  operating_system_type       = var.vm_operating_system_type
  initialization_datastore_id = var.vm_initialization_datastore_id

  vms = {
    "cp-1" = {
      name                = "cp-1"
      vm_id               = var.control_plane_vm_id_base + 1
      disk_size           = var.control_plane_disk_size
      disk_import_file_id = data.terraform_remote_state.base.outputs.cloud_image_file_id
      memory_dedicated    = var.control_plane_memory_dedicated
      cpu_cores           = var.control_plane_cpu_cores
      tags                = ["k8s", "control-plane"]
      initialization = {
        user_data_file_id = proxmox_virtual_environment_file.cloud_init_control_plane["cp-1"].id
        ipv4_address      = "${local.cp1_ip}/24"
        ipv4_gateway      = var.vm_ipv4_gateway
        username          = "rocky"
        password          = var.vm_rocky_password
        ssh_keys          = []
      }
    }
  }
}

module "control_plane_join_2" {
  count      = contains(local.cp_slots, 2) ? 1 : 0
  source     = "../modules/vm"
  depends_on = [module.control_plane_bootstrap, null_resource.wait_for_cp0]

  node_name                   = var.vm_node_name
  disk_datastore_id           = var.vm_disk_datastore_id
  disk_interface              = var.vm_disk_interface
  disk_iothread               = var.vm_disk_iothread
  disk_discard                = var.vm_disk_discard
  disk_speed_read             = var.vm_disk_speed_read
  disk_speed_write            = var.vm_disk_speed_write
  network_device_bridge       = var.vm_network_device_bridge
  network_device_vlan_tag     = var.vm_network_device_vlan_tag
  operating_system_type       = var.vm_operating_system_type
  initialization_datastore_id = var.vm_initialization_datastore_id

  vms = {
    "cp-2" = {
      name                = "cp-2"
      vm_id               = var.control_plane_vm_id_base + 2
      disk_size           = var.control_plane_disk_size
      disk_import_file_id = data.terraform_remote_state.base.outputs.cloud_image_file_id
      memory_dedicated    = var.control_plane_memory_dedicated
      cpu_cores           = var.control_plane_cpu_cores
      tags                = ["k8s", "control-plane"]
      initialization = {
        user_data_file_id = proxmox_virtual_environment_file.cloud_init_control_plane["cp-2"].id
        ipv4_address      = "${local.cp2_ip}/24"
        ipv4_gateway      = var.vm_ipv4_gateway
        username          = "rocky"
        password          = var.vm_rocky_password
        ssh_keys          = []
      }
    }
  }
}

module "control_plane_join_3" {
  count      = contains(local.cp_slots, 3) ? 1 : 0
  source     = "../modules/vm"
  depends_on = [module.control_plane_bootstrap, null_resource.wait_for_cp0]

  node_name                   = var.vm_node_name
  disk_datastore_id           = var.vm_disk_datastore_id
  disk_interface              = var.vm_disk_interface
  disk_iothread               = var.vm_disk_iothread
  disk_discard                = var.vm_disk_discard
  disk_speed_read             = var.vm_disk_speed_read
  disk_speed_write            = var.vm_disk_speed_write
  network_device_bridge       = var.vm_network_device_bridge
  network_device_vlan_tag     = var.vm_network_device_vlan_tag
  operating_system_type       = var.vm_operating_system_type
  initialization_datastore_id = var.vm_initialization_datastore_id

  vms = {
    "cp-3" = {
      name                = "cp-3"
      vm_id               = var.control_plane_vm_id_base + 3
      disk_size           = var.control_plane_disk_size
      disk_import_file_id = data.terraform_remote_state.base.outputs.cloud_image_file_id
      memory_dedicated    = var.control_plane_memory_dedicated
      cpu_cores           = var.control_plane_cpu_cores
      tags                = ["k8s", "control-plane", "replacement"]
      initialization = {
        user_data_file_id = proxmox_virtual_environment_file.cloud_init_control_plane["cp-3"].id
        ipv4_address      = "${local.cp3_ip}/24"
        ipv4_gateway      = var.vm_ipv4_gateway
        username          = "rocky"
        password          = var.vm_rocky_password
        ssh_keys          = []
      }
    }
  }
}

module "control_plane_join_4" {
  count      = contains(local.cp_slots, 4) ? 1 : 0
  source     = "../modules/vm"
  depends_on = [module.control_plane_bootstrap, null_resource.wait_for_cp0]

  node_name                   = var.vm_node_name
  disk_datastore_id           = var.vm_disk_datastore_id
  disk_interface              = var.vm_disk_interface
  disk_iothread               = var.vm_disk_iothread
  disk_discard                = var.vm_disk_discard
  disk_speed_read             = var.vm_disk_speed_read
  disk_speed_write            = var.vm_disk_speed_write
  network_device_bridge       = var.vm_network_device_bridge
  network_device_vlan_tag     = var.vm_network_device_vlan_tag
  operating_system_type       = var.vm_operating_system_type
  initialization_datastore_id = var.vm_initialization_datastore_id

  vms = {
    "cp-4" = {
      name                = "cp-4"
      vm_id               = var.control_plane_vm_id_base + 4
      disk_size           = var.control_plane_disk_size
      disk_import_file_id = data.terraform_remote_state.base.outputs.cloud_image_file_id
      memory_dedicated    = var.control_plane_memory_dedicated
      cpu_cores           = var.control_plane_cpu_cores
      tags                = ["k8s", "control-plane", "replacement"]
      initialization = {
        user_data_file_id = proxmox_virtual_environment_file.cloud_init_control_plane["cp-4"].id
        ipv4_address      = "${local.cp4_ip}/24"
        ipv4_gateway      = var.vm_ipv4_gateway
        username          = "rocky"
        password          = var.vm_rocky_password
        ssh_keys          = []
      }
    }
  }
}

module "worker_nodes" {
  for_each = local.worker_map

  source     = "../modules/vm"
  depends_on = [null_resource.wait_for_cp0]

  node_name                   = var.vm_node_name
  disk_datastore_id           = var.vm_disk_datastore_id
  disk_interface              = var.vm_disk_interface
  disk_iothread               = var.vm_disk_iothread
  disk_discard                = var.vm_disk_discard
  disk_speed_read             = var.vm_disk_speed_read
  disk_speed_write            = var.vm_disk_speed_write
  network_device_bridge       = var.vm_network_device_bridge
  network_device_vlan_tag     = var.vm_network_device_vlan_tag
  operating_system_type       = var.vm_operating_system_type
  initialization_datastore_id = var.vm_initialization_datastore_id

  vms = {
    (each.key) = each.value
  }
}
