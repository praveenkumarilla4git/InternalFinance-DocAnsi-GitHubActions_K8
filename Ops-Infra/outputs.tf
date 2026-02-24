# --- 1. The Main Entry Point ---
# This is the only URL users (and you) should use now.
output "alb_dns_name" {
  description = "The public URL of the Load Balancer"
  value       = "http://${aws_lb.finance_alb.dns_name}"
}

# --- 2. SRE Health Endpoint ---
output "health_check_url" {
  description = "The direct link to the SRE Health Telemetry"
  value       = "http://${aws_lb.finance_alb.dns_name}/health"
}

# --- 3. ASG Details ---
output "autoscaling_group_name" {
  description = "The name of the Auto Scaling Group managing the nodes"
  value       = aws_autoscaling_group.finance_asg.name
}

# --- 4. Active Nodes (Optional for Debugging) ---
# Note: This lists the IPs currently active in the ASG
output "active_node_ips" {
  description = "Current public IPs of instances in the ASG"
  value       = data.aws_instances.asg_nodes.public_ips
}