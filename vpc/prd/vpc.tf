locals {
  azs = ["${var.region}a", "${var.region}b"]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_primary_cidr

  secondary_cidr_blocks = [var.vpc_secondary_cidr]
  azs                   = local.azs

  # bastion, LB 용도 (NAT GW도 여기 배치) — AZ별 /27 (32 IPs)
  public_subnets = [
    cidrsubnet(var.vpc_primary_cidr, 3, 0),
    cidrsubnet(var.vpc_primary_cidr, 3, 1),
  ]

  # EKS 노드 전용 — AZ별 /26 (64 IPs)
  private_subnets = [
    cidrsubnet(var.vpc_primary_cidr, 2, 1),
    cidrsubnet(var.vpc_primary_cidr, 2, 2),
  ]

  enable_nat_gateway     = true
  one_nat_gateway_per_az = true
  enable_dns_hostnames   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "subnet-type"                     = "node"
  }
}

# Pod 전용 서브넷 (보조 CIDR) — AZ별 /22 (1024 IPs)
resource "aws_subnet" "pod_subnets" {
  count             = length(local.azs)
  vpc_id            = module.vpc.vpc_id
  cidr_block        = cidrsubnet(var.vpc_secondary_cidr, 2, count.index)
  availability_zone = local.azs[count.index]

  tags = {
    Name                              = "${var.cluster_name}-pod-${local.azs[count.index]}"
    "kubernetes.io/role/internal-elb" = 1
    "subnet-type"                     = "pod"
  }
}

# one_nat_gateway_per_az = true 이므로 AZ별 route table 사용
resource "aws_route_table_association" "pod_subnets_routing" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.pod_subnets[count.index].id
  route_table_id = module.vpc.private_route_table_ids[count.index]
}
