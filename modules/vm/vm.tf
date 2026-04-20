resource "proxmox_virtual_environment_vm" "vm" {
  for_each = var.vms

  name      = each.value.name
  node_name = coalesce(each.value.node_name, var.node_name)
  keyboard_layout = each.value.keyboard_layout

  description = each.value.description
  tags        = each.value.tags
  vm_id       = each.value.vm_id

  stop_on_destroy = each.value.stop_on_destroy

  dynamic "agent" {
    for_each = each.value.agent_enabled != null ? [1] : []
    content {
      enabled = each.value.agent_enabled
    }
  }

  # Disk from cloud image (no local download; Proxmox uses downloaded file) or empty disk.
  # When importing: set size >= image base (~10GB for Rocky) and >= existing disk to avoid "shrinking disks is not supported".
  dynamic "disk" {
    for_each = each.value.disk_import_file_id != null ? [1] : []
    content {
      import_from  = each.value.disk_import_file_id
      datastore_id = coalesce(each.value.disk_datastore_id, var.disk_datastore_id)
      interface    = coalesce(each.value.disk_interface, var.disk_interface)
      iothread     = coalesce(each.value.disk_iothread, var.disk_iothread)
      discard      = coalesce(each.value.disk_discard, var.disk_discard)
      size         = each.value.disk_size
      file_format  = each.value.disk_file_format

      dynamic "speed" {
        for_each = coalesce(each.value.disk_speed_read, var.disk_speed_read) != null || coalesce(each.value.disk_speed_write, var.disk_speed_write) != null ? [1] : []
        content {
          read  = coalesce(each.value.disk_speed_read, var.disk_speed_read)
          write = coalesce(each.value.disk_speed_write, var.disk_speed_write)
        }
      }
    }
  }
  dynamic "disk" {
    for_each = each.value.disk_import_file_id == null ? [1] : []
    content {
      datastore_id = coalesce(each.value.disk_datastore_id, var.disk_datastore_id)
      interface    = coalesce(each.value.disk_interface, var.disk_interface)
      iothread     = coalesce(each.value.disk_iothread, var.disk_iothread)
      discard      = coalesce(each.value.disk_discard, var.disk_discard)
      size         = each.value.disk_size
      file_format  = each.value.disk_file_format

      dynamic "speed" {
        for_each = coalesce(each.value.disk_speed_read, var.disk_speed_read) != null || coalesce(each.value.disk_speed_write, var.disk_speed_write) != null ? [1] : []
        content {
          read  = coalesce(each.value.disk_speed_read, var.disk_speed_read)
          write = coalesce(each.value.disk_speed_write, var.disk_speed_write)
        }
      }
    }
  }

  dynamic "cdrom" {
    for_each = each.value.cdrom_file_id != null ? [1] : []
    content {
      file_id   = each.value.cdrom_file_id
      interface = each.value.cdrom_interface
    }
  }

  dynamic "network_device" {
    for_each = coalesce(each.value.network_device_bridge, var.network_device_bridge) != "" ? [1] : []
    content {
      bridge  = coalesce(each.value.network_device_bridge, var.network_device_bridge)
      vlan_id = coalesce(each.value.network_device_vlan_tag, var.network_device_vlan_tag, 0)
    }
  }

  operating_system {
    type = coalesce(each.value.operating_system_type, var.operating_system_type)
  }

  memory {
    dedicated      = each.value.memory_dedicated
    floating       = each.value.memory_floating
    keep_hugepages = each.value.memory_keep_hugepages
    shared         = each.value.memory_shared
  }

  cpu {
    cores      = each.value.cpu_cores
    flags      = each.value.cpu_flags
    hotplugged = each.value.cpu_hotplugged
    limit      = each.value.cpu_limit
    numa       = each.value.cpu_numa
    sockets    = each.value.cpu_sockets
    type       = each.value.cpu_type
    units      = each.value.cpu_units
  }

  bios = each.value.bios

  # Initialization (cloud-init). ip_config defaults to DHCP when ipv4_address is null.
  dynamic "initialization" {
    for_each = each.value.initialization != null ? [1] : []
    content {
      datastore_id      = coalesce(each.value.initialization.datastore_id, var.initialization_datastore_id)
      user_data_file_id = each.value.initialization.user_data_file_id

      ip_config {
        ipv4 {
          address = each.value.initialization.ipv4_address != null ? each.value.initialization.ipv4_address : "dhcp"
          gateway = each.value.initialization.ipv4_address != null ? each.value.initialization.ipv4_gateway : null
        }
      }

      dynamic "user_account" {
        for_each = each.value.initialization.username != null || each.value.initialization.password != null || length(coalesce(each.value.initialization.ssh_keys, [])) > 0 ? [1] : []
        content {
          username = each.value.initialization.username
          password = each.value.initialization.password
          keys     = coalesce(each.value.initialization.ssh_keys, [])
        }
      }
    }
  }

  lifecycle {
    # Cloud-init/bootstrap is first-boot only; updating the snippet reference later should not recreate the VM.
    ignore_changes = [initialization[0].user_data_file_id]
  }
}
