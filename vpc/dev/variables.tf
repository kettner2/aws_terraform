variable "cluster_name" {
  description = "EKS 클러스터 이름"
  type        = string
}

variable "region" {
  description = "AWS 리전"
  type        = string
}

variable "vpc_primary_cidr" {
  description = "VPC 기본 대역 (노드용, /24)"
  type        = string
}

variable "vpc_secondary_cidr" {
  description = "VPC 보조 대역 (Pod 전용, /20)"
  type        = string
}

variable "aws_profile" {
  description = "사용할 AWS CLI 프로필 이름"
  type        = string
}