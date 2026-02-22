terraform {
  backend "s3" {
    bucket = "tf-state-praveen2-2025"
    key    = "finance-app/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

# --- Data Sources (To fetch Default VPC info) ---
data "aws_vpc" "default" { default = true }
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# --- Security Group 1: The Load Balancer (The Gatekeeper) ---
resource "aws_security_group" "alb_sg" {
  name        = "finance-alb-sg"
  description = "Public HTTP access for the ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- Security Group 2: The EC2 Instances (The Workers) ---
resource "aws_security_group" "finance_docker_sg" {
  name        = "finance-docker-sg"
  description = "Restricted access: SSH from world, App from ALB only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description     = "Flask App from ALB"
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    # SRE BEST PRACTICE: Only allow traffic coming from the ALB Security Group
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- EC2 Instances ---
resource "aws_instance" "finance_server" {
  count                  = var.instance_count
  ami                    = "ami-068c0051b15cdb816"
  instance_type          = "t3.micro"
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.finance_docker_sg.id]

  # --- THIS IS THE MAGIC LINE ---
  # It takes the list of 6 subnets and assigns:
  # Instance 1 -> Subnet 1 (AZ-a)
  # Instance 2 -> Subnet 2 (AZ-b)
  # Instance 3 -> Subnet 3 (AZ-c)
  subnet_id = data.aws_subnets.default.ids[count.index % length(data.aws_subnets.default.ids)]

  tags = {
    Name = "Finance-Node-${count.index + 1}"
  }
  
  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y docker git
              service docker start
              systemctl enable docker
              usermod -a -G docker ec2-user
              EOF
}

# --- Load Balancer Components ---

resource "aws_lb" "finance_alb" {
  name               = "finance-app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "finance_tg" {
  name     = "finance-app-tg"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    port                = "5000"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 10 # Aggressive health check for faster demo feedback
  }
}

resource "aws_lb_listener" "finance_listener" {
  load_balancer_arn = aws_lb.finance_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.finance_tg.arn
  }
}

resource "aws_lb_target_group_attachment" "tg_attach" {
  count            = var.instance_count
  target_group_arn = aws_lb_target_group.finance_tg.arn
  target_id        = aws_instance.finance_server[count.index].id
  port             = 5000
}

# --- Dynamic Ansible Inventory ---
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../Ansible/hosts.ini"
  content  = <<EOT
[webserver]
%{ for ip in aws_instance.finance_server.*.public_ip ~}
${ip} ansible_user=ec2-user ansible_ssh_private_key_file=key.pem ansible_ssh_common_args='-o StrictHostKeyChecking=no'
%{ endfor ~}
EOT
}