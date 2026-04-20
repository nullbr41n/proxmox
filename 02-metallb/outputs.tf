output "metallb_namespace" {
  description = "Namespace where MetalLB is installed."
  value       = helm_release.metallb.namespace
}
