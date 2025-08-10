# bgp/proxmox requires 1.3.0 or higher and hashicorp switched to BSL after 1.5.7 (will test with OpenTofu later)
terraform {
  required_version = ">= 1.3.0, < 1.5.8"
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      version = ">= 0.70.0"
    }
  }
}

# provider configuration, see: https://registry.terraform.io/providers/bpg/proxmox/latest/docs#example-usage
provider "proxmox" {
  api_token = var.bpg_provider["api_token"]
  insecure = var.bpg_provider["insecure"]
  endpoint = var.bpg_provider["endpoint"]

  ssh {
    agent       = var.bpg_provider["agent"]
    username    = var.bpg_provider["username"]
    private_key = file("${var.bpg_provider["private_key_file"]}")
  }
}

# variable to store provider configuration, populate these in your local terraform.tfvars
variable "bpg_provider" {
  description = "list of bpg proxmox provider configuration details"
  type = object({
    agent             = bool 
    api_token         = string
    endpoint          = string
    insecure          = bool
    private_key_file  = string
    username          = string
  })
  default = null
}

# variable to define common proxmox details like datastores for disks, iso, snippets
variable "proxmox" {
  description = "list of pve configuration details like datastore disks, iso, snippets"
  type = object({
    datastore_id_disks    = string # where to store vm disks
    datastore_id_iso      = string # where to store iso images
    datastore_id_snippets = string # where to store snippets for things like user-data cloud-init
    node_name             = string # which proxmox node to use
  })
  default = {
    datastore_id_disks    = "local-lvm"
    datastore_id_iso      = "local"
    datastore_id_snippets = "local"
    node_name             = "pve"
  }
}

# variable to store jenkins agent configuration, populate these in your local terraform.tfvars
variable "jenkins" {
  description = "list of jenkins details like master ip, secret"
  type = object({
    master_url  = string # master url like "http://jenkins.lan:1880"
    secret      = string # secret used when connecting into the master host
    working_dir = string # jenkins working dir
  })
  default = null
}

variable "virtualmachine" {
  description = "list of virtualmachine configuration details like name, cpu, memory"
  type = object({
    hostname = string # hostname of the vm
    id       = number # id to assign to vm (must be unique globally in proxmox)
    ip       = string # ip address to assign to vm like "192.168.1.40/24"
    cpu      = number # number of cpu to assign to vm
    domain   = string # domain to assigin to vm (will be used with hostname for fqdn)
    gateway  = string # networking gateway like "192.168.1.1"
    memory   = number # amount of memory to assign to vm
    bridge   = string # pve bridge to use for vm networking, typically vmbr0 unless you've setup additional bridges/networks
  })
  default = {
    hostname = "jenkins-agent-vm"
    id       = 9040
    ip       = "192.168.1.40/24"
    cpu      = 2
    domain   = "lan"
    gateway  = "192.168.1.1"
    memory   = 4096
    bridge   = "vmbr0"
  }
}

# variable to store the ssh public key file location so we can access our virtual machines later (may move to virtual machines later)
variable "ssh_pub_key_file" {
  description = "ssh public key file that'll be used in places like user-data authorized keys"
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

# upload the noble cloudimg to the iso datastore
resource "proxmox_virtual_environment_download_file" "image" {
  content_type = "iso"
  datastore_id = var.proxmox["datastore_id_iso"]
  file_name    = "tf-bpg-pve-jenkins-agent_noble-server-cloudimg-amd64.img"
  node_name    = var.proxmox["node_name"] 

  url = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

# generate user-data cloud-init from our template
data "template_file" "user_data_cloud_config" {

  template = file("templates/user-data.yaml.tpl")

  vars = {
    fqdn           = "${var.virtualmachine["hostname"]}.${var.virtualmachine["domain"]}"
    hostname       = var.virtualmachine["hostname"]
    username       = "jenkins"
    ssh_public_key = trimspace(file("${var.ssh_pub_key_file}"))
    secret         = var.jenkins["secret"]
    master_url     = var.jenkins["master_url"]
    working_dir    = var.jenkins["working_dir"]
  }

}

# upload our generated user-data cloud-init to the snippets datastore
resource "proxmox_virtual_environment_file" "user_data_cloud_config" {

  content_type = "snippets"
  datastore_id = var.proxmox["datastore_id_snippets"]
  node_name    = var.proxmox["node_name"]

  source_raw {
    data = data.template_file.user_data_cloud_config.rendered
    file_name    = "${var.virtualmachine["id"]}-user-data-cloud-config.yaml"
  }

}

resource "proxmox_virtual_environment_vm" "vm" {
  name      = "${var.virtualmachine["hostname"]}"
  vm_id     = var.virtualmachine["id"] 
  node_name = var.proxmox["node_name"]

  agent {
    enabled = true
  }

  cpu {
    cores = var.virtualmachine["cpu"]
  }

  memory {
    dedicated = var.virtualmachine["memory"]
  }

  disk {
    datastore_id = var.proxmox["datastore_id_disks"] 
    file_id      = proxmox_virtual_environment_download_file.image.id
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = 20
  }

  initialization {
    ip_config {
      ipv4 {
        address = var.virtualmachine["ip"] 
        gateway = var.virtualmachine["gateway"]
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.user_data_cloud_config.id
  }

  network_device {
    bridge = var.virtualmachine["bridge"]
  }

}

output "vm_ipv4_address" {
  value = proxmox_virtual_environment_vm.vm.ipv4_addresses[1][0]
}