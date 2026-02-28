# =============================================================================
# PHASE 1: STATE MANAGEMENT & BACKEND
# Why: SREs never store "terraform.tfstate" locally. If your laptop dies, the 
# infrastructure is lost. Using S3 ensures a "Single Source of Truth" and 
# allows team collaboration via State Locking.
# =============================================================================
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

# =============================================================================
# PHASE 2: DYNAMIC DATA DISCOVERY
# Why: Hardcoding IDs (like vpc-123) makes code brittle. 
# We use Data Sources to "query" AWS in real-time. 
# We filter out 'us-east-1e' because it lacks t3.micro capacity, ensuring 
# deployment reliability (99% success target).
# =============================================================================
data "aws_vpc" "default" { 
  default = true 
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "availability-zone"
    values = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1f"]
  }
}

# =============================================================================
# PHASE 3: IDENTITY & ACCESS MANAGEMENT (IAM)
# Why: Security Best Practice. We don't put AWS Keys inside EC2 instances. 
# Instead, we give the EC2 an "Identity" (Role) that AWS recognizes. 
# The "ReadOnly" policy ensures the server can PULL images but cannot 
# DELETE them, following the Principle of Least Privilege.
# =============================================================================
resource "aws_iam_role" "ec2_ecr_role" {
  name = "finance-app-ec2-ecr-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  role       = aws_iam_role.ec2_ecr_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# This profile is the 'container' that attaches the Role to the EC2 instance.
resource "aws_iam_instance_profile" "ec2_ecr_profile" {
  name = "finance-app-ec2-ecr-profile"
  role = aws_iam_role.ec2_ecr_role.name
}

# =============================================================================
# PHASE 4: NETWORK SECURITY (FIREWALLS)
# Why: Layered Defense. 
# ALB SG: Open to the world on Port 80.
# App SG: ONLY accepts traffic from the ALB on Port 5000. 
# This prevents hackers from bypassing the Load Balancer to hit your app directly.
# =============================================================================
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

# =============================================================================
# PHASE 5: THE LAUNCH TEMPLATE (IMMUTABLE INFRASTRUCTURE)
# Why: Instead of "building" code on every server (slow/error-prone), 
# we "Pull" a pre-built image from ECR. This ensures environment consistency.
# If the image works in GitHub Actions, it WILL work on this EC2.
# =============================================================================
resource "aws_launch_template" "finance_lt" {
  name_prefix   = "finance-app-lt-"
  image_id      = "ami-068c0051b15cdb816" # Amazon Linux 2023
  instance_type = "t3.micro"
  key_name      = var.key_name

  iam_instance_profile { 
    name = aws_iam_instance_profile.ec2_ecr_profile.name 
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.finance_docker_sg.id]
  }

  user_data = base64encode(<<-EOF
#!/bin/bash
dnf update -y
dnf install -y docker aws-cli
service docker start
systemctl enable docker
usermod -a -G docker ec2-user

# Authenticate Docker to ECR using the EC2 Instance Profile Identity
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 770771424969.dkr.ecr.us-east-1.amazonaws.com

# Stop existing containers to avoid port conflicts during instance refresh
docker stop finance-app || true
docker rm finance-app || true

# Pull the 'latest' image built and pushed by GitHub Actions
docker pull 770771424969.dkr.ecr.us-east-1.amazonaws.com/finance-app:latest
docker run -d --name finance-app -p 5000:5000 770771424969.dkr.ecr.us-east-1.amazonaws.com/finance-app:latest
EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = { Name = "Finance-ASG-Node" }
  }
}

# =============================================================================
# PHASE 6: AUTO SCALING & SELF-HEALING
# Why: High Availability. 
# instance_refresh: This is your "Rolling Update" strategy. 
# When the Launch Template version changes, ASG replaces instances automatically. 
# min_healthy_percentage = 50 ensures your app stays online during updates.
# =============================================================================
resource "aws_autoscaling_group" "finance_asg" {
  name                = "finance-asg"
  desired_capacity    = var.desired_capacity
  max_size            = var.max_size
  min_size            = var.min_size
  target_group_arns   = [aws_lb_target_group.finance_tg.arn]
  vpc_zone_identifier = data.aws_subnets.default.ids

  launch_template {
    id      = aws_launch_template.finance_lt.id
    version = "$Latest" 
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50 
    }
  }

  health_check_type         = "ELB" # Use Application Load Balancer health checks
  health_check_grace_period = 300   # Give Docker 5 mins to start before marking 'Unhealthy'
}

# =============================================================================
# PHASE 7: LOAD BALANCING (THE FRONT END)
# Why: Distributes traffic across Multiple Availability Zones (AZs). 
# Health Checks: Monitors port 5000. If the Flask app crashes, the ALB 
# stops sending traffic to that specific node immediately (Auto-Isolation).
# =============================================================================
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
    path                = var.health_check_path 
    port                = "5000"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
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

# =============================================================================
# PHASE 8: DYNAMIC INVENTORY FOR ANSIBLE
# Why: Terraform builds the hardware; Ansible manages the software.
# This block generates your inventory file dynamically based on the 
# real-time running IP addresses of your ASG nodes.
# =============================================================================
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