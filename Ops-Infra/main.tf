# 1. State Management (S3 Backend)
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

  # This explicitly tells AWS to stay away from us-east-1e
  filter {
    name   = "availability-zone"
    values = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1f"]
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
  description = "Restricted access: App from ALB only"
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

# --- Launch Template ---
resource "aws_launch_template" "finance_lt" {
  name_prefix   = "finance-app-lt-"
  image_id      = "ami-068c0051b15cdb816"
  instance_type = "t3.micro"
  key_name      = var.key_name

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.finance_docker_sg.id]
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y docker git
              service docker start
              systemctl enable docker
              usermod -a -G docker ec2-user
              cd /home/ec2-user
              git clone https://github.com/praveenkumarilla4git/InternalFinance-DocAnsi-GitHubActions_K8.git app
              cd app
              docker build -t finance-app-v2 .
              docker run -d --name finance-app -p 5000:5000 finance-app-v2
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = { Name = "Finance-ASG-Node" }
  }
}

# --- Auto Scaling Group ---
resource "aws_autoscaling_group" "finance_asg" {
  desired_capacity    = var.desired_capacity
  max_size            = var.max_size
  min_size            = var.min_size
  target_group_arns   = [aws_lb_target_group.finance_tg.arn]
  vpc_zone_identifier = data.aws_subnets.default.ids

  launch_template {
    id      = aws_launch_template.finance_lt.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 300
}

# --- Load Balancer ---
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
    enabled             = true
    interval            = 30
    path                = var.health_check_path 
    port                = "5000"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    matcher             = "200"
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

# --- Dynamic Ansible Inventory ---
data "aws_instances" "asg_nodes" {
  instance_tags = { Name = "Finance-ASG-Node" }
  instance_state_names = ["running"]
  depends_on           = [aws_autoscaling_group.finance_asg]
}

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../Ansible/hosts.ini"
  content  = <<EOT
[webserver]
%{ for ip in data.aws_instances.asg_nodes.public_ips ~}
${ip} ansible_user=ec2-user ansible_ssh_private_key_file=key.pem ansible_ssh_common_args='-o StrictHostKeyChecking=no'
%{ endfor ~}
EOT
}