# AWS基本設定
provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = "ap-northeast-1"
}

data "aws_iam_role" "executionRole"{
  name = "ecsTaskExecutionRole"
}

resource "aws_ecs_task_definition" "task" {
  cpu = "1024"
  memory = "4096"

  network_mode = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn = data.aws_iam_role.executionRole.arn
  container_definitions = jsonencode([
    {
      logConfiguration: {
        logDriver: "awslogs",
        options: {
          awslogs-group: "/ecs/gitlab",
          awslogs-region: "ap-northeast-1",
          awslogs-stream-prefix: "ecs"
        }
      },
      portMappings: [
        {
          hostPort: 80,
          protocol: "tcp",
          containerPort: 80
        }
      ],
      cpu: 1024,
      memoryReservation: 4096,
      essential: true,
      name: "gitlab",
      image: "gitlab/gitlab-ce:latest"
    }
  ])
  family = "gitlab"
}

resource "aws_ecs_cluster" "gitlab" {
  name = "gitlab"
}

resource "aws_vpc" "gitlab" {
  cidr_block = "10.0.0.0/16"

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "gitlab"
  }
}

resource "aws_internet_gateway" "gitlab" {
  vpc_id = aws_vpc.gitlab.id

  tags = {
    Name = "gitlab"
  }
}

resource "aws_default_route_table" "public" {
  tags = {
    Name = "public-rt"
  }
  default_route_table_id = aws_vpc.gitlab.default_route_table_id
}

resource "aws_route" "public" {
  route_table_id = aws_default_route_table.public.id
  gateway_id = aws_internet_gateway.gitlab.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_subnet" "public-subnet" {
  cidr_block = "10.0.10.0/24"
  availability_zone = "ap-northeast-1a"
  vpc_id = aws_vpc.gitlab.id
  map_public_ip_on_launch = true
  tags = {
    Name = "gitlab-public"
  }
}

resource "aws_security_group" "gitlab-sg" {
  vpc_id = aws_vpc.gitlab.id
  name = "gitlab-sg"
  ingress {
    from_port = 80
    protocol = "TCP"
    to_port = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_service" "gitlab" {
  name = "gitlab-ecs"
  cluster = aws_ecs_cluster.gitlab.arn
  task_definition = "gitlab:7"
  desired_count = 1

  launch_type = "FARGATE"
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent = 200
  network_configuration {
    subnets = [
      aws_subnet.public-subnet.id
    ]

    security_groups = [
      aws_security_group.gitlab-sg.id
    ]

    assign_public_ip = true
  }

}
