output "argocd_application_name" {
  description = "Name of the Argo CD bootstrap Application."
  value       = kubernetes_manifest.argocd_apps.manifest.metadata.name
}
