variable "proxmox_endpoint" {
  description = "Proxmox API endpoint URL."
  type        = string
}

variable "proxmox_token_id" {
  description = "Proxmox API token ID."
  type        = string
  sensitive   = true
}

variable "proxmox_token_secret" {
  description = "Proxmox API token secret."
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification for the Proxmox API."
  type        = bool
  default     = true
}

variable "proxmox_ssh_user" {
  description = "SSH user for node-level Proxmox actions."
  type        = string
}

variable "proxmox_ssh_node_name" {
  description = "Proxmox node name used by the provider SSH block."
  type        = string
}

variable "proxmox_ssh_node_address" {
  description = "Hostname or IP of the Proxmox node used for SSH."
  type        = string
}

variable "proxmox_ssh_port" {
  description = "SSH port for the Proxmox node."
  type        = number
  default     = 22
}

variable "cloud_image_url" {
  description = "URL of the guest cloud image to download."
  type        = string
}

variable "cloud_image_datastore_id" {
  description = "Directory-backed datastore for the downloaded cloud image."
  type        = string
  default     = "local"
}

variable "cloud_image_node_name" {
  description = "Proxmox node where the image file will be downloaded."
  type        = string
}

variable "cloud_image_file_name" {
  description = "Optional explicit filename for the downloaded cloud image."
  type        = string
  default     = null
}
