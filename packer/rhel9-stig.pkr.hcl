# STIG-hardened RHEL 9 image, with OpenSCAP scans before and after hardening.
# Run from the repo's main folder:  packer build packer

packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

# Leave empty to use the default VPC. If you have no default VPC,
# put a public subnet ID from your dev app here (see guide step 5.2).
variable "subnet_id" {
  type    = string
  default = ""
}

locals {
  datastream = "/usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml"
  profile    = "xccdf_org.ssgproject.content_profile_stig"
  playbook   = "/usr/share/scap-security-guide/ansible/rhel9-playbook-stig.yml"
}

source "amazon-ebs" "rhel9" {
  region                      = var.region
  instance_type               = "t3.medium"
  ssh_username                = "ec2-user"
  ami_name                    = "portfolio-rhel9-stig-{{timestamp}}"
  encrypt_boot                = true
  subnet_id                   = var.subnet_id
  associate_public_ip_address = true

  # Only allow SSH from this computer's public IP (a /32), never 0.0.0.0/0.
  # Otherwise the Step 4 auto-fix would close Packer's SSH access mid-build.
  temporary_security_group_source_public_ip = true

  source_ami_filter {
    filters = {
      name                  = "RHEL-9.*_HVM-*-x86_64-*-Hourly2-GP3"
      architecture          = "x86_64"
      "virtualization-type" = "hvm"
      "root-device-type"    = "ebs"
    }
    owners      = ["309956199498"] # Red Hat's official AWS account
    most_recent = true
  }

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name      = "portfolio-rhel9-stig"
    Project   = "cloud-portfolio-app"
    ManagedBy = "packer"
  }
}

build {
  sources = ["source.amazon-ebs.rhel9"]

  # Install the tools, then scan BEFORE hardening
  provisioner "shell" {
    inline = [
      "sudo dnf install -y openscap-scanner scap-security-guide ansible-core",
      "sudo ansible-galaxy collection install ansible.posix community.general",
      "sudo oscap xccdf eval --profile ${local.profile} --report /home/ec2-user/stig-before.html ${local.datastream} || true",
      "sudo chown ec2-user /home/ec2-user/stig-before.html"
    ]
  }

  # Apply the DISA STIG settings, then scan AFTER hardening.
  # Both run inside ONE root session, because the STIG itself turns on
  # "sudo requires a password", which would block a separate sudo call later.
  provisioner "shell" {
    remote_folder = "/home/ec2-user"
    inline = [
      "sudo bash -c 'ansible-playbook -i localhost, -c local ${local.playbook} || echo Some STIG tasks failed, the after scan shows what was applied; oscap xccdf eval --profile ${local.profile} --report /home/ec2-user/stig-after.html ${local.datastream} || true; chown ec2-user /home/ec2-user/stig-after.html'"
    ]
  }

  # Bring both reports back to your computer
  provisioner "file" {
    direction   = "download"
    source      = "/home/ec2-user/stig-before.html"
    destination = "packer/reports/stig-before.html"
  }
  provisioner "file" {
    direction   = "download"
    source      = "/home/ec2-user/stig-after.html"
    destination = "packer/reports/stig-after.html"
  }
}
