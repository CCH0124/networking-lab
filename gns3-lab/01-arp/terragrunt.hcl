include "root" {
  path = find_in_parent_folders()
}

# 指向我們想要部署的 OpenTofu 模組
terraform {
  source = "../modules/gns3-topology"
}

inputs = {
  project_name       = "01-first-testing-lab"
}