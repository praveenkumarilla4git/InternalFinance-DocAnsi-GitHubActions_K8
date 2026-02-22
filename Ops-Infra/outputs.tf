# 1. Individual Clickable Links for each server (For Smoke Testing)
output "app_links" {
  description = "Clickable URLs to verify each Finance Server individually"
  value       = [for ip in aws_instance.finance_server.*.public_ip : "http://${ip}:5000"]
}

# 2. Map of Instance ID to IP (For SRE Troubleshooting)
output "instance_details" {
  description = "Map of Instance IDs to their Public IPs for quick AWS Console lookup"
  value = {
    for inst in aws_instance.finance_server : inst.id => inst.public_ip
  }
}

# 3. Keep your original list for script compatibility
output "server_ips" {
  description = "Raw list of public IPs for legacy script ingestion"
  value       = aws_instance.finance_server.*.public_ip
}