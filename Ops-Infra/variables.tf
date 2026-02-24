variable "aws_region" {
  description = "The AWS region to deploy resources"
  default     = "us-east-1"
}

variable "desired_capacity" {
  description = "Number of EC2 instances to maintain"
  type        = number
  default     = 3
}

variable "min_size" {
  description = "Minimum instances for High Availability"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum instances for scaling"
  type        = number
  default     = 5
}

variable "key_name" {
  description = "Name of your existing EC2 Key Pair"
  default     = "batch3" 
}

variable "health_check_path" {
  description = "SRE observability path"
  default     = "/health"
}

variable "aws_access_key" {
  type      = string
  sensitive = true 
}

variable "aws_secret_key" {
  type      = string
  sensitive = true
}