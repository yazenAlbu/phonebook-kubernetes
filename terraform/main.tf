terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "Terraform"
    }
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "master" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3a.medium"
  key_name                    = var.key_name
  associate_public_ip_address = true
  user_data                   = file("${path.module}/master.sh")
  vpc_security_group_ids      = [aws_security_group.tf-k8s-master-sec-gr.id]

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "${var.project_name}-master"
  }
}

resource "aws_instance" "worker" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3a.medium"
  key_name                    = var.key_name
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2connectprofile.name
  vpc_security_group_ids      = [aws_security_group.tf-k8s-master-sec-gr.id]
  user_data = templatefile("${path.module}/worker.sh", {
    region         = "us-east-1"
    master-id      = aws_instance.master.id
    master-zone    = aws_instance.master.availability_zone
    master-private = aws_instance.master.private_ip
  })

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "${var.project_name}-worker"
  }

  depends_on = [aws_iam_role_policy.ec2connectcli_policy]
}

resource "aws_iam_instance_profile" "ec2connectprofile" {
  name = "${var.project_name}-worker"
  role = aws_iam_role.ec2connectcli.name
}

resource "aws_iam_role" "ec2connectcli" {
  name = "${var.project_name}-worker"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "ec2connectcli_policy" {
  name = "${var.project_name}-join-master"
  role = aws_iam_role.ec2connectcli.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ec2-instance-connect:SendSSHPublicKey"
        Resource = aws_instance.master.arn
        Condition = {
          StringEquals = {
            "ec2:osuser" = "ubuntu"
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances", "ec2:DescribeInstanceStatus"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_security_group" "tf-k8s-master-sec-gr" {
  name   = "${var.project_name}-cluster"
  vpc_id = data.aws_vpc.default.id

  ingress {
    description = "Communication between cluster nodes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    description = "SSH from the operator"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  ingress {
    description = "Phonebook management"
    from_port   = 30001
    to_port     = 30001
    protocol    = "tcp"
    cidr_blocks = [var.web_cidr]
  }

  ingress {
    description = "Phonebook search"
    from_port   = 30002
    to_port     = 30002
    protocol    = "tcp"
    cidr_blocks = [var.web_cidr]
  }

  ingress {
    description = "Unified phonebook ingress"
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    cidr_blocks = [var.web_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-cluster"
  }
}

variable "project_name" {
  type    = string
  default = "phonebook"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,31}$", var.project_name))
    error_message = "Use 2-32 lowercase letters, digits, or hyphens, starting with a letter."
  }
}

variable "key_name" {
  type    = string
  default = "linuspass"
}

variable "ssh_cidr" {
  type        = string
  description = "Your public IPv4 address followed by /32."

  validation {
    condition     = can(cidrnetmask(var.ssh_cidr)) && endswith(var.ssh_cidr, "/32")
    error_message = "Supply one IPv4 address with /32, for example 203.0.113.10/32."
  }
}

variable "web_cidr" {
  type        = string
  description = "IPv4 network allowed to open the application."
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrnetmask(var.web_cidr))
    error_message = "Supply a valid IPv4 CIDR."
  }
}

output "master_instance_id" {
  value = aws_instance.master.id
}

output "worker_instance_id" {
  value = aws_instance.worker.id
}

output "master_public_dns" {
  value = aws_instance.master.public_dns
}

output "master_private_dns" {
  value = aws_instance.master.private_dns
}

output "worker_public_dns" {
  value = aws_instance.worker.public_dns
}

output "worker_private_dns" {
  value = aws_instance.worker.private_dns
}

output "ingress_url" {
  value = "http://${aws_instance.master.public_dns}:30080"
}
