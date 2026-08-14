locals {
  cloud_image_file_name = coalesce(var.cloud_image_file_name, basename(var.cloud_image_url))
}

# Rocky GenericCloud.latest: overwrite=true re-downloads when upstream
# Content-Length changes so replace-node starts from a current golden image.
# First-boot package_upgrade in 01-cluster cloud-init then brings packages current.
resource "proxmox_virtual_environment_download_file" "cloud_image" {
  content_type = "import"
  datastore_id = var.cloud_image_datastore_id
  node_name    = var.cloud_image_node_name
  url          = var.cloud_image_url
  file_name    = local.cloud_image_file_name
  overwrite    = true
}
