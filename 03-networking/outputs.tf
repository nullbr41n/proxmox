output "metallb_ip_pool_name" {
  description = "MetalLB IPAddressPool name."
  value       = kubernetes_manifest.metallb_ip_pool.manifest.metadata.name
}

output "metallb_l2_advertisement_name" {
  description = "MetalLB L2Advertisement name."
  value       = kubernetes_manifest.metallb_l2_advertisement.manifest.metadata.name
}
