output "server_ips" {
  # The '*' tells Terraform to grab the public_ip from ALL instances in the list
  value = aws_instance.finance_server.*.public_ip
}