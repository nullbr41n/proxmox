variable "kubeconfig_path" {
  description = "Path to kubeconfig with admin access. If empty, uses KUBECONFIG env or the default kubeconfig search path."
  type        = string
  default     = ""
}

variable "proxmox_endpoint" {
  description = "Proxmox API endpoint URL reused for the CSI config secret."
  type        = string
}

variable "proxmox_token_id" {
  description = "Proxmox API token ID reused for the CSI config secret."
  type        = string
  sensitive   = true
}

variable "proxmox_token_secret" {
  description = "Proxmox API token secret reused for the CSI config secret."
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification for the Proxmox API in the CSI config secret."
  type        = bool
  default     = true
}

variable "argocd_server_service_type" {
  description = "Argo CD server Service type."
  type        = string
  default     = "ClusterIP"
}

variable "argocd_hostname" {
  description = "Hostname exposed by the Argo CD ingress."
  type        = string
  default     = "argocd.intra.nixbin.com"
}

variable "argocd_apps_repo_url" {
  description = "Git repo URL for the Argo CD app-of-apps repository registration."
  type        = string
}

variable "argocd_apps_repo_type" {
  description = "Repository type for Argo CD."
  type        = string
  default     = "git"
}

variable "argocd_apps_repo_username" {
  description = "Optional username for the Argo CD repository."
  type        = string
  default     = ""
  sensitive   = true
}

variable "argocd_apps_repo_password" {
  description = "Optional password or token for the Argo CD repository."
  type        = string
  default     = ""
  sensitive   = true
}

variable "argocd_apps_repo_ssh_private_key" {
  description = "Optional SSH private key for the Argo CD repository."
  type        = string
  default     = ""
  sensitive   = true
}

variable "argocd_apps_repo_insecure_ignore_host_key" {
  description = "Whether Argo CD should skip SSH host key verification for the repository."
  type        = bool
  default     = false
}
