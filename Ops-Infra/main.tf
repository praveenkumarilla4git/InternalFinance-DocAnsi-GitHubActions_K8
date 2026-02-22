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

# --- Data Sources ---
data "aws_vpc" "default" { default = true }
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# --- Security Groups ---
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

  # Multi-AZ Distribution
  subnet_id = data.aws_subnets.default.ids[count.index % length(data.aws_subnets.default.ids)]

  tags = {
    Name = "Finance-Node-${count.index + 1}"
  }
  
  user_data = <<-EOF
              #!/bin/bash
              # 1. System Setup
              dnf update -y
              dnf install -y docker git
              service docker start
              systemctl enable docker
              usermod -a -G docker ec2-user

              # 2. Self-Bootstrap Application
              cd /home/ec2-user
              if [ ! -d "app" ]; then
                git clone https://github.com/praveenkumarilla4git/InternalFinance-DocAnsi-GitHubActions_K8.git app
              fi
              cd app
              git pull origin main

              # 3. Docker Launch (Named container for Ansible to find/replace later)
              docker build -t finance-app-v2 .
              docker run -d --name finance-app -p 5000:5000 finance-app-v2
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

  # --- UPDATED HEALTH CHECK TWEAKS ---
  health_check {
    path                = "/"
    port                = "5000"
    healthy_threshold   = 2
    unhealthy_threshold = 3    # Give Docker extra time to build/start
    timeout             = 5
    interval            = 20   # Longer interval prevents ALB from giving up too fast
    matcher             = "200-399" # Accept 200 (OK) and 302 (Redirect)
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