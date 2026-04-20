data "terraform_remote_state" "base" {
  backend = "local"

  config = {
    path = "${path.module}/../00-base/terraform.tfstate"
  }
}
