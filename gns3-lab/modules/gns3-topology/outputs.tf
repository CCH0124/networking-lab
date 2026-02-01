output "gns3_project_id" {
  description = "ID of the created GNS3 project."
  value       = gns3_project.lab_project.project_id
}

output "gns3_project_url" {
  description = "URL to open the project in the GNS3 Web UI."
  # 注意: 這裡我們需要一個 gns3_server_url 變數，但為了模組通用性，
  # 我們可以選擇在 Terragrunt 層組合它，或者在這裡也加入一個變數。
  # 為了簡單起見，我們只輸出 ID。
  value       = "Project ID: ${gns3_project.lab_project.project_id}"
}