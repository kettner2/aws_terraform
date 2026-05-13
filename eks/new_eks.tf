# 1. EKS 클러스터 본체 및 기본 Addon (🌟 노드 그룹은 여기서 만들지 않습니다!)
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.34"
  cluster_endpoint_public_access = true
  cluster_endpoint_public_access_cidrs = ["14.39.199.71/32"]
  enable_cluster_creator_admin_permissions = true

  vpc_id                   = data.aws_vpc.selected.id
  subnet_ids               = data.aws_subnets.private.ids
  control_plane_subnet_ids = data.aws_subnets.private.ids

  # 🌟 핵심 1: 노드 그룹을 메인 모듈에서 완전히 제거(비움)합니다.
  eks_managed_node_groups = {} 

  # 🌟 핵심 2: vpc-cni를 처음부터 커스텀 설정으로 배포합니다.
  cluster_addons = {
    vpc-cni = {
      before_compute = true # 노드가 뜨기 전에 무조건 먼저 설치
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      service_account_role_arn    = module.vpc_cni_irsa_role.iam_role_arn
      configuration_values = jsonencode({
        env = {
          AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG = "true"
          ENI_CONFIG_LABEL_DEF               = "topology.kubernetes.io/zone"
          ENABLE_PREFIX_DELEGATION           = "true"
          WARM_PREFIX_TARGET                 = "1"
        }
      })
    }
  }
}

# 2. Kubeconfig 업데이트
resource "null_resource" "update_kubeconfig" {
  triggers = { cluster_name = module.eks.cluster_name }
  provisioner "local-exec" {
    interpreter = ["powershell", "-Command"]
    command     = <<-EOF
      aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name} --profile stt --alias test
      Start-Sleep -Seconds 10
    EOF
  }
  depends_on = [module.eks]
}

# 3. ENIConfig YAML 생성
resource "local_file" "eniconfig_yaml" {
  for_each = data.aws_subnet.pod_subnets
  filename = "${path.module}/eniconfig-${each.value.availability_zone}.yaml"
  content  = <<-YAML
  apiVersion: crd.k8s.amazonaws.com/v1alpha1
  kind: ENIConfig
  metadata:
    name: ${each.value.availability_zone}
  spec:
    securityGroups:
      - ${module.eks.node_security_group_id}
      - ${aws_security_group.custom_node_sg.id} 
    subnet: ${each.value.id}
  YAML
}

# 4. ENIConfig 배포 (🌟 노드가 없어도 API 서버에 정상적으로 등록됩니다)
resource "null_resource" "eniconfig" {
  for_each = data.aws_subnet.pod_subnets
  triggers = {
    file_hash = md5(local_file.eniconfig_yaml[each.key].content)
  }
  depends_on = [
    null_resource.update_kubeconfig,
    local_file.eniconfig_yaml,
    module.eks 
  ]
  provisioner "local-exec" {
    command = "kubectl apply -f ${local_file.eniconfig_yaml[each.key].filename}"
  }
}

# 5. 🌟 노드 그룹 독립 생성 (ENIConfig가 세팅된 이후에 노드를 투입!)
module "eks_managed_node_group" {
  source  = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = "~> 20.0"

  name            = "test-eks-node"
  cluster_name    = module.eks.cluster_name
  cluster_version = module.eks.cluster_version

  subnet_ids = data.aws_subnets.private.ids
  cluster_service_cidr = module.eks.cluster_service_cidr
  # EKS 클러스터 통신을 위한 필수 보안 그룹 매핑
  cluster_primary_security_group_id = module.eks.cluster_primary_security_group_id
  vpc_security_group_ids = [
    module.eks.node_security_group_id,
    aws_security_group.custom_node_sg.id
  ]

  instance_types = ["t3.medium"]
  min_size       = 2
  max_size       = 3
  desired_size   = 2

  # 🌟 핵심 3: 반드시 ENIConfig 배포가 끝난 후에만 노드가 생성되도록 강제
  depends_on = [null_resource.eniconfig]
}


# 🌟 수정 2: 노드 그룹 생성이 끝난 후 안전하게 애드온 배포
resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [module.eks_managed_node_group]
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [module.eks_managed_node_group]
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  service_account_role_arn    = module.ebs_csi_irsa_role.iam_role_arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [module.eks_managed_node_group]
}

resource "aws_eks_addon" "s3_csi" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "aws-mountpoint-s3-csi-driver"
  service_account_role_arn    = module.s3_csi_irsa_role.iam_role_arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [module.eks_managed_node_group]
}

# # 6. 추가 Helm Addon 배포
# module "eks_blueprints_addons" {
#   source  = "aws-ia/eks-blueprints-addons/aws"
#   version = "~> 1.16"

#   cluster_name      = module.eks.cluster_name
#   cluster_endpoint  = module.eks.cluster_endpoint
#   cluster_version   = module.eks.cluster_version
#   oidc_provider_arn = module.eks.oidc_provider_arn

#   enable_aws_load_balancer_controller = true
#   enable_metrics_server = true
#   enable_external_dns   = true
#   external_dns = { #external-dns IRSA 오류로 인해, 연결 작업
#     role_arn = module.external_dns_irsa_role.iam_role_arn

#     values = [
#       <<-EOT
#         serviceAccount:
#           create: true
#           name: external-dns-sa
#           namespace: external-dns
#           annotations:
#             eks.amazonaws.com/role-arn: "${module.external_dns_irsa_role.iam_role_arn}"
#       EOT
#     ]
#   }

#   depends_on = [module.eks_managed_node_group]
# }

# 1단계: LBC, metrics-server, external-dns 먼저 설치
module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.16"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_aws_load_balancer_controller = true
  enable_metrics_server               = true
  enable_external_dns                 = true

  external_dns = {
    role_arn = module.external_dns_irsa_role.iam_role_arn

    values = [
      <<-EOT
        serviceAccount:
          create: true
          name: external-dns-sa
          namespace: external-dns
          annotations:
            eks.amazonaws.com/role-arn: "${module.external_dns_irsa_role.iam_role_arn}"
      EOT
    ]
  }

  depends_on = [module.eks_managed_node_group]
}

module "eks_blueprints_addons_argocd" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.16"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_argocd = true

  # K8s 프로바이더 대신 Helm 차트 자체 기능으로 Ingress 생성
  # 개발환경에서 http로 접속하도록 extraArgs. insecure 삽입
  # 도메인 적용안했으므로 hosts ""
  argocd = {
    values = [
      <<-EOT
      server:
        extraArgs:
          - --insecure
        ingress:
          enabled: true
          ingressClassName: alb
          annotations:
            alb.ingress.kubernetes.io/scheme: internet-facing
            alb.ingress.kubernetes.io/target-type: ip
            alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
            alb.ingress.kubernetes.io/backend-protocol: HTTP
            alb.ingress.kubernetes.io/healthcheck-protocol: HTTP
            alb.ingress.kubernetes.io/healthcheck-path: /healthz
          hosts:
            - ""
          paths:
            - /
          pathType: Prefix
      EOT
    ]
  }

  depends_on = [module.eks_blueprints_addons] # (또는 설정해둔 대기 리소스)
}

# 1. Helm 배포 완료 후, AWS ALB가 생성되고 DNS가 붙을 때까지 충분히 대기합니다.
resource "time_sleep" "wait_for_alb" {
  depends_on = [module.eks_blueprints_addons_argocd]
  
  # ALB 프로비저닝에 보통 2~3분이 소요되므로 3분(180초) 대기를 설정합니다.
  create_duration = "3m"
}

resource "null_resource" "print_argocd_info" {
  provisioner "local-exec" {
    command     = "kubectl get ingress -n argocd"
    interpreter = ["powershell", "-Command"]
  }

  provisioner "local-exec" {
    command     = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | % { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }"
    interpreter = ["powershell", "-Command"]
  }

  depends_on = [time_sleep.wait_for_alb]
}

resource "null_resource" "delete_argocd_ingress" {
  provisioner "local-exec" {
    when    = destroy
    command = "kubectl delete ingress --all -A --ignore-not-found; Start-Sleep -Seconds 180"
    interpreter = ["powershell", "-Command"]
  }

  depends_on = [
    module.eks_blueprints_addons_argocd, 
    module.eks_blueprints_addons, 
    null_resource.print_argocd_info, 
    aws_eks_addon.kube_proxy, 
    aws_eks_addon.coredns
  ]
}