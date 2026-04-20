output "cloud_image_file_id" {
  description = "File ID of the downloaded cloud image."
  value       = proxmox_virtual_environment_download_file.cloud_image.id
}
