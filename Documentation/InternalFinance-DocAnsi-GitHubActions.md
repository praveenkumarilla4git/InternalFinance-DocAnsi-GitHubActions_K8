DevOps Project: InternalFinance (Docker + Terraform + Ansible + GitHub Actions)
Objective: Deploy a Python Flask application on AWS EC2 using Docker for containerization, Terraform for infrastructure provisioning, Ansible for configuration management, and GitHub Actions for continuous deployment.

Author: Praveen Status: Completed (Fully Automated)

Phase 1: Project Setup (Local)
Create the following folder structure for your project:

Plaintext

InternalFinance-DocAnsi-GitHubActions/
├── app/
│   ├── main.py
│   ├── core.py
│   ├── schema.py
│   └── templates/
│       └── index.html
├── Ops-Infra/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars  <-- DO NOT COMMIT THIS (Contains Keys)
├── Ansible/
│   └── deploy.yml
├── .github/
│   └── workflows/
│       └── deploy.yml
├── Dockerfile
├── requirements.txt
└── .gitignore
1. Key Application Files
Dockerfile

Dockerfile

FROM python:3.10-slim
WORKDIR /finance_docker_app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ ./app/
WORKDIR /finance_docker_app/app
RUN python schema.py
EXPOSE 5000
CMD ["python", "main.py"]
requirements.txt

Plaintext

Flask
.gitignore (Crucial for Security)

Plaintext

*.pem
*.tfstate
*.tfstate.backup
.terraform/
finance.db
__pycache__/
terraform.tfvars
Phase 2: Infrastructure as Code (Terraform)
We use Terraform to launch an AWS EC2 instance and configure the Security Group.

Location: Ops-Infra/main.tf

Terraform

provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

resource "aws_security_group" "finance_docker_sg" {
  name        = "finance-docker-sg"
  description = "Allow SSH and Port 5000"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
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

resource "aws_instance" "finance_server" {
  ami             = "ami-068c0051b15cdb816" # Amazon Linux 2023 (US-East-1)
  instance_type   = "t3.micro"
  key_name        = var.key_name
  security_groups = [aws_security_group.finance_docker_sg.name]

  tags = {
    Name = "Finance-Docker-Server"
  }
}
Execution Commands:

PowerShell

cd Ops-Infra
terraform init
terraform apply -auto-approve
Result: Copy the server_ip from the output (e.g., 44.222.182.167).

Phase 3: Configuration Management (Ansible)
We use Ansible to automate the manual steps (Git clone, Docker build, Docker run).

Location: Ansible/deploy.yml

YAML

---
- name: Deploy Finance App Automated
  hosts: webserver
  become: yes
  vars:
    # Update this to your specific repository URL
    repo_url: "https://github.com/praveenkumarilla4git/InternalFinance-DocAnsi-GitHubActions.git"
    project_dir: "/home/ec2-user/finance-app-cicd"
    image_name: "finance-app-v2"

  tasks:
    - name: Ensure Docker service is running
      service:
        name: docker
        state: started
        enabled: yes

    - name: Pull latest code
      git:
        repo: "{{ repo_url }}"
        dest: "{{ project_dir }}"
        version: main
        force: yes

    # Fix logic for requirements.txt location
    - name: Check if requirements.txt exists in app/ folder
      stat:
        path: "{{ project_dir }}/app/requirements.txt"
      register: req_file

    - name: Move requirements.txt to main folder
      command: mv {{ project_dir }}/app/requirements.txt {{ project_dir }}/
      when: req_file.stat.exists

    - name: Stop and remove existing container
      shell: |
        docker stop $(docker ps -q --filter ancestor={{ image_name }}) || true
        docker rm $(docker ps -aq --filter ancestor={{ image_name }}) || true

    - name: Build Docker Image
      shell: "docker build -t {{ image_name }} ."
      args:
        chdir: "{{ project_dir }}"

    - name: Run Docker Container
      shell: "docker run -d -p 5000:5000 {{ image_name }}"
Phase 4: CI/CD Pipeline (GitHub Actions)
We use GitHub Actions to trigger the deployment automatically whenever code is pushed to main.

1. Configure Secrets
Go to GitHub Repo -> Settings -> Secrets and variables -> Actions. Add:

EC2_HOST: Your Server IP (e.g., 44.222.182.167)

EC2_USER: ec2-user

EC2_SSH_KEY: Content of your .pem file.

2. Workflow File
Location: .github/workflows/deploy.yml

YAML

name: Deploy to EC2

on:
  push:
    branches:
      - main

jobs:
  deploy:
    name: Build and Deploy
    runs-on: ubuntu-latest

    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Deploy via SSH
        uses: appleboy/ssh-action@v1.0.0
        with:
          host: ${{ secrets.EC2_HOST }}
          username: ${{ secrets.EC2_USER }}
          key: ${{ secrets.EC2_SSH_KEY }}
          port: 22
          script: |
            # 1. Bootstrap: Install Ansible & Git on the server
            sudo dnf update -y
            sudo dnf install -y ansible-core git

            # 2. Workspace Setup
            mkdir -p /home/ec2-user/ansible_cicd
            cd /home/ec2-user/ansible_cicd

            # 3. Dynamic Inventory (Replaces hosts.ini)
            echo "[webserver]" > hosts
            echo "localhost ansible_connection=local" >> hosts

            # 4. Download Playbook
            # Ensure this Raw URL matches your repo path exactly
            curl -o deploy.yml https://raw.githubusercontent.com/praveenkumarilla4git/InternalFinance-DocAnsi-GitHubActions/main/Ansible/deploy.yml

            # 5. Execute Ansible
            ansible-playbook -i hosts deploy.yml
Phase 5: How to Deploy
Make Changes: Edit your code (e.g., change the title in index.html).

Push to GitHub:

PowerShell

git add .
git commit -m "Update application title"
git push origin main
Watch Automation:

Go to the Actions tab in GitHub.

Wait for the workflow to turn Green.

Verify:

Visit: http://<YOUR_EC2_IP>:5000

Phase 6: Cost Management (Cleanup)
Important: When finished, destroy the infrastructure to stop AWS billing.

PowerShell

cd Ops-Infra
terraform destroy -auto-approve