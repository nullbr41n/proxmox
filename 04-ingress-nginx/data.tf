data "terraform_remote_state" "networking" {
  backend = "local"

  config = {
    path = "${path.module}/../03-networking/terraform.tfstate"
  }
}
