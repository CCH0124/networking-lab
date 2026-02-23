resource "gns3_qemu_node" "CiscoIOSvL2-1" {
  project_id     = gns3_project.lab_project.project_id
  name           = "CiscoIOSvL2-1"
  adapter_type   = "e1000"
  adapters       = 16
  hda_disk_image = "vios_l2-adventerprisek9-m.SSA.high_iron_20180619.qcow2"
  console_type   = "telnet"
  cpus           = 1
  ram            = 768
  platform       = "x86_64"
  start_vm       = true
}