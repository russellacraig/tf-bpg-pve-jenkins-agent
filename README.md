# tf-bpg-pve-jenkins-agent
Deploy a Jenkins Agent VM (Ubuntu Based) running docker and other useful packages in pipelines on an existing [Proxmox VE](https://www.proxmox.com/en/products/proxmox-virtual-environment/overview) host for homelab scenarios using [Terraform](https://www.hashicorp.com/en/products/terraform) leveraging the [bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox/latest/docs) provider

> [!IMPORTANT]
> Tested with PVE 8.4.1, Terraform 1.5.7 and bpg/proxmox 0.70.0.\
> Requirements may change in PVE 9.x and have not been tested (by me).

This was created quickly and purely for disposable homelab testing... as such there are a few security caveats below:
> [!IMPORTANT]
> The user-data.tpl will contain the jenkins agent secret once rendered and uploaded...\
> This can potentially expose it to other users from the snippets store on PVE in multiuser scenarios (unlikely a homelab issue)\
> Similarly, a wrapper script hasn't been created so the secret is also exposed in a ps listing and the systemd unit file (unlikely a homelab issue)...\
> Strongly consider secure options like terraform and ansible, with a jenkins agent wrapper script for real world provisioning scenarios

The onboarding steps can be skipped if you've already configured this for bpg/proxmox
## Terraform PVE Onboarding (API)
SSH to your PVE instance:
```bash
$ ssh root@pve.lan
```
Create the user PVE terraform account:
```bash
$ pveum user add terraform@pve
```
Create the PVE terraform role with required privledges:
```bash
$ pveum role add Terraform -privs "\
Datastore.Allocate \
Datastore.AllocateSpace \
Datastore.AllocateTemplate \
Datastore.Audit Pool.Allocate \
Sys.Audit \
Sys.Console \
Sys.Modify \
SDN.Use \
VM.Allocate \
VM.Audit \
VM.Clone \
VM.Config.CDROM \
VM.Config.Cloudinit \
VM.Config.CPU \
VM.Config.Disk \
VM.Config.HWType \
VM.Config.Memory \
VM.Config.Network \
VM.Config.Options \
VM.Migrate \
VM.Monitor \
VM.PowerMgmt \
User.Modify"
```
Assign the PVE terraform role to the PVE terraform user account:
```bash
$ pveum aclmod / -user terraform@pve -role Terraform
```
Create a token for the pve terraform user account:
> [!IMPORTANT]
> Record this for terraform.tfvars, you will not be able to recover this later.
```bash
$ pveum user token add terraform@pve token -privsep 0
```
Enable snippets on local storage:
```bash
$ pvesm set local --content vztmpl,backup,iso,snippets
```
## Terraform PVE Onboarding (SSH)
Due to limitations with the PVE API, some provider actions must be performed via SSH, so create a linux system user on the PVE host:
```bash
$ useradd -m terraform
```
Install sudo:
```bash
$ apt install sudo
```
Add the terraform user to sudoers:
```bash
$ visudo -f /etc/sudoers.d/terraform
```
Content to be added to /etc/sudoers.d/terraform:
```
terraform ALL=(root) NOPASSWD: /sbin/pvesm
terraform ALL=(root) NOPASSWD: /sbin/qm
terraform ALL=(root) NOPASSWD: /usr/bin/tee /var/lib/vz/*
```
Add your public key to the authorized_keys of the terraform account:
```bash
$ mkdir ~terraform/.ssh
$ chmod 700 ~terraform/.ssh
# add the public key you're going to use with the provider to the authorized_keys
$ vi ~terraform/.ssh/authorized_keys
$ chmod 600 ~terraform/.ssh/authorized_keys
$ chown -R terraform:terraform ~terraform/.ssh
```
Verify connectivity from your workstation that you'll be excuting the terraform from:
```bash
$ ssh terraform@pve.lan "sudo pvesm apiinfo"
```
## Providers Configuration (terraform.tfvars)
An example is provided (terraform.tfvars.example) which you can use as a reference:
```
bpg_provider = {
    agent            = false
    api_token        = "terraform@pve!token=00000000-0000-0000-0000-000000000000"
    endpoint         = "https://proxmox-hostname-or-ip-address:8006/"
    insecure         = true
    private_key_file = "~/.ssh/id_ed25519"
    username         = "terraform"
}

jenkins = {
    master_url = "http://jenkins-master-hostname-or-ip:8080"
    secret = "00000000000000000000000000000000000000000000000000000000000"
    working_dir = "/opt/jenkins"
}
```
Copy the example to terraform.tfvars and update with your details.

## Terraform Deployment
```bash
$ terraform init
$ terraform plan
$ terraform apply
```
## Terraform Cleanup
```bash
$ terraform destroy
```
## Terraform Variables
The variables are declared in main.tf with their defaults (These might be moved to a variables.tf later) and you can override as needed... the virtualmachine defaults are below:
```
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
```