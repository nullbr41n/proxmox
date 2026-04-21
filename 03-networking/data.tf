data "terraform_remote_state" "metallb" {
  backend = "local"

  config = {
    path = "${path.module}/../02-metallb/terraform.tfstate"
  }
}
