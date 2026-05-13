resource "aws_security_group" "custom_node_sg" {
  name        = "${var.cluster_name}-custom-sg"
  description = "Temporary allow-all security group for EKS nodes"
  
  # 앞서 작성한 data 블록에서 찾아온 VPC ID를 사용합니다.
  vpc_id      = data.aws_vpc.selected.id 

  # 인바운드: 모든 트래픽 허용 (테스트용)
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # -1은 모든 프로토콜을 의미
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 아웃바운드: 모든 트래픽 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-custom-node-sg"
  }
}