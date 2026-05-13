locals {
  azs = ["${var.region}a", "${var.region}b", "${var.region}c"]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_primary_cidr

  # 1. 보조 대역(Secondary CIDR) 추가
  secondary_cidr_blocks = [var.vpc_secondary_cidr]

  azs = local.azs

  # 2. 기본 대역(/24) 쪼개기
  # 노드(EC2)가 배치될 프라이빗 서브넷 (각 /26 = 64개 IP)
  private_subnets = ["192.168.0.0/26", "192.168.0.64/26", "192.168.0.128/26"]
  # NAT 및 로드밸런서용 퍼블릭 서브넷 (각 /28 = 16개 IP)
  public_subnets  = ["192.168.0.192/28", "192.168.0.208/28", "192.168.0.224/28"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "subnet-type" = "node"
  }
}

# ==========================================
# 3. Pod 전용 서브넷 직접 생성 (보조 대역 사용)
# ==========================================
resource "aws_subnet" "pod_subnets" {
  count             = length(local.azs)
  vpc_id            = module.vpc.vpc_id
  # 100.64.0.0/20을 3개의 /22 대역(각 1024개 IP)으로 나눔
  cidr_block        = cidrsubnet(var.vpc_secondary_cidr, 2, count.index)
  availability_zone = local.azs[count.index]

  tags = {
    Name = "${var.cluster_name}-pod-subnet-${local.azs[count.index]}"
    "kubernetes.io/role/internal-elb" = 1
    "subnet-type" = "pod"
  }
}

# Pod들도 인터넷(NAT)으로 나갈 수 있도록 기존 라우팅 테이블에 연결
resource "aws_route_table_association" "pod_subnets_routing" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.pod_subnets[count.index].id
  route_table_id = module.vpc.private_route_table_ids[0]
}





