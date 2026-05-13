# [2-eks/provider.tf]

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    # 🌟 추가: kubernetes_manifest 리소스 사용을 위해 필수 (eniconfig)
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
  }
}

# AWS 프로바이더 설정
provider "aws" {
  region  = var.region
  profile = "stt"
}

# 🌟 중요: data 대신 module.eks의 결과값을 직접 참조하여 인증 에러 해결
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.default.token
  }
  repository_config_path = "${path.module}/helm/repositories.yaml"
  repository_cache       = "${path.module}/helm/cache"
}


# 🌟 추가: ENIConfig 배포를 위한 쿠버네티스 프로바이더 설정
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.eks.cluster_name
    ]
  }
}