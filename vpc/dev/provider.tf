# [1-vpc/provider.tf] 와 [2-eks/provider.tf] 내용

terraform {
  # 테라폼 자체의 최소 버전 요구사항
  required_version = ">= 1.0"

  # 사용할 프로바이더(AWS)와 플러그인 버전 지정
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # AWS 5.x 대역의 최신 버전을 사용하겠다는 의미
    }
  }
}

# 실제 AWS 계정 연결 설정
provider "aws" {
  region  = var.region
  profile = var.aws_profile
}