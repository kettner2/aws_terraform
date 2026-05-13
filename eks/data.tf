# [2-eks/data.tf]

# 생성된 EKS 클러스터의 엔드포인트 및 인증서 정보 조회
data "aws_eks_cluster" "default" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}

# EKS 클러스터에 접근하기 위한 임시 토큰 발급
data "aws_eks_cluster_auth" "default" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}



# 1. 1-vpc 폴더에서 만든 VPC 찾아오기 (이름으로 검색)
data "aws_vpc" "selected" {
  filter {
    name   = "tag:Name"
    values = ["${var.cluster_name}-vpc"] 
  }
}


# 노드 전용 서브넷 (기존 프라이빗, 192.168.x.x 대역)
data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
  tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "subnet-type" = "node"   # ← VPC 구성할 때 노드 서브넷에만 이 태그를 붙여야 함
  }
}

# Pod 전용 서브넷 (보조 CIDR, 100.64.x.x 대역)
data "aws_subnets" "pod" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
  tags = {
    "subnet-type" = "pod"    # ← Pod 서브넷에만 붙은 태그
  }
}

# ENIConfig 생성용 — Pod 서브넷만 조회
data "aws_subnet" "pod_subnets" {
  for_each = toset(data.aws_subnets.pod.ids)  # private → pod 로 변경
  id       = each.value
}
