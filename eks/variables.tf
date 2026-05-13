variable "cluster_name" {
  description = "EKS 클러스터 이름"
  type        = string
  default     = "test-eks"
}

variable "region" {
  description = "AWS 리전"
  type        = string
  default     = "eu-central-1"
}

variable "vpc_primary_cidr" {
  description = "VPC 기본 대역 (노드용, /24)"
  type        = string
  default     = "192.168.0.0/24"
}

variable "vpc_secondary_cidr" {
  description = "VPC 보조 대역 (Pod 전용, /20)"
  type        = string
  default     = "100.64.0.0/20"
}