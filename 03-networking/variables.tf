variable "kubeconfig_path" {
  description = "Path to kubeconfig with admin access. If empty, uses KUBECONFIG env or the default kubeconfig search path."
  type        = string
  default     = ""
}

variable "metallb_ip_addresses" {
  description = "MetalLB IP address pool or range. Must not overlap with node IPs."
  type        = string
}
