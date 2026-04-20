provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = "${var.proxmox_token_id}=${var.proxmox_token_secret}"
  insecure  = var.proxmox_insecure

  ssh {
    username = var.proxmox_ssh_user
    agent    = true

    node {
      name    = var.proxmox_ssh_node_name
      address = var.proxmox_ssh_node_address
      port    = var.proxmox_ssh_port
    }
  }
}
