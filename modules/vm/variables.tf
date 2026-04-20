# Module-level defaults (passed from root; no defaults here so caller uses tfvars).
variable "node_name" {
  description = "Proxmox node for VMs."
  type        = string
}

variable "disk_datastore_id" {
  description = "Datastore for VM disks."
  type        = string
}

variable "disk_interface" {
  description = "Disk interface (e.g. scsi0)."
  type        = string
}

variable "disk_iothread" {
  description = "Enable disk iothread."
  type        = bool
}

variable "disk_discard" {
  description = "Disk discard (e.g. ignore, on)."
  type        = string
}

variable "disk_speed_read" {
  description = "Maximum disk read speed in MB/s."
  type        = number
  default     = null
}

variable "disk_speed_write" {
  description = "Maximum disk write speed in MB/s."
  type        = number
  default     = null
}

variable "network_device_bridge" {
  description = "Bridge for VM NIC."
  type        = string
}
variable "network_device_vlan_tag" {
  description = "VLAN tag for VM NIC (0 = no VLAN)."
  type        = number
  default     = 0
}

variable "operating_system_type" {
  description = "Guest OS type (e.g. l26)."
  type        = string
}

variable "initialization_datastore_id" {
  description = "Datastore for cloud-init drive."
  type        = string
}

variable "vms" {
  description = "Map of virtual machines to create (only VM-unique fields; generic defaults come from module variables)."
  type = map(object({
    name              = string
    node_name         = optional(string, null)      # null = use var.node_name
    keyboard_layout   = optional(string, "en-us")
    description       = optional(string, null)
    tags              = optional(list(string), null)
    vm_id             = optional(number, null)
    stop_on_destroy   = optional(bool, false)
    agent_enabled     = optional(bool, null)
    disk_datastore_id = optional(string, null)
    disk_interface    = optional(string, null)
    disk_iothread     = optional(bool, null)
    disk_discard      = optional(string, null)
    disk_speed_read   = optional(number, null)
    disk_speed_write  = optional(number, null)
    disk_size         = optional(number, 20)
    disk_file_format  = optional(string, null)
    disk_import_file_id = optional(string, null)
    cdrom_file_id     = optional(string, null)
    cdrom_interface   = optional(string, null)
    network_device_bridge   = optional(string, null)
    network_device_vlan_tag = optional(number, null)
    operating_system_type = optional(string, null)
    memory_dedicated     = optional(number, 1024)
    memory_floating      = optional(number, 0)
    memory_keep_hugepages = optional(bool, false)
    memory_shared        = optional(number, 0)
    cpu_cores      = optional(number, 1)
    cpu_flags      = optional(list(string), [])
    cpu_hotplugged = optional(number, 0)
    cpu_limit      = optional(number, 0)
    cpu_numa       = optional(bool, false)
    cpu_sockets    = optional(number, 1)
    cpu_type       = optional(string, "host")
    cpu_units      = optional(number, 1)
    bios           = optional(string, null)
    initialization = optional(object({
      datastore_id       = optional(string, null)  # null = use var.initialization_datastore_id
      user_data_file_id  = optional(string, null) # custom cloud-init snippet; requires SSH for upload
      ipv4_address       = optional(string, null)
      ipv4_gateway       = optional(string, null)
      username           = optional(string, null)
      password           = optional(string, null)
      ssh_keys           = optional(list(string), [])
    }), null)
  }))
}
