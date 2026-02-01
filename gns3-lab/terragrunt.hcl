terraform_binary = "tofu"

locals {
  gns3_server_url    = "http://172.25.150.200:3080"
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_providers {
    gns3 = {
      source  = "NetOpsChic/gns3"
      version = ">= 2.5"
    }
  }
}

provider "gns3" {
  host = "${local.gns3_server_url}"
}
EOF
}

# 設定 Terragrunt 狀態檔的存放位置 (這裡設定為本地)
remote_state {
  backend = "local"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite"
  }
  config = {
    path = "${get_terragrunt_dir()}/terraform.tfstate"
  }
}

# 為所有子專案傳入共用的 inputs
inputs = {
  gns3_server_url = local.gns3_server_url
}