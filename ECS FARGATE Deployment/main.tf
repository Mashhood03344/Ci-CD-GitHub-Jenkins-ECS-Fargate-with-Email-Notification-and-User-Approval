# ECS Task Execution Role for the ECS Task definition
resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "ecs-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_assume_role_policy.json
}

data "aws_iam_policy_document" "ecs_task_execution_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecs_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_policy" "ecs_policy" {
  name        = "ecs-policy"
  description = "Permissions for ECS tasks to access ECR and logs"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_policy_attachment" {
  policy_arn = aws_iam_policy.ecs_policy.arn
  role       = aws_iam_role.ecs_task_execution_role.name
}





# Create a VPC
resource "aws_vpc" "html_app_vpc" {
  cidr_block = var.vpc_cidr
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "html-app-vpc"
  }
}

# Create an Internet Gateway
resource "aws_internet_gateway" "html_app_igw" {
  vpc_id = aws_vpc.html_app_vpc.id
  tags = {
    Name = "html-app-igw"
  }
}

# Create a Subnet
resource "aws_subnet" "html_app_subnet1" {
  vpc_id            = aws_vpc.html_app_vpc.id
  cidr_block        = var.subnet_cidr1
  availability_zone = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags = {
    Name = "html-app-subnet"
  }
}

# Create a Subnet
resource "aws_subnet" "html_app_subnet2" {
  vpc_id            = aws_vpc.html_app_vpc.id
  cidr_block        = var.subnet_cidr2
  availability_zone = "${var.aws_region}b"
  map_public_ip_on_launch = true
  tags = {
    Name = "html-app-subnet"
  }
}

# Create a Route Table
resource "aws_route_table" "html_app_route_table" {
  vpc_id = aws_vpc.html_app_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.html_app_igw.id
  }

  tags = {
    Name = "html-app-route-table"
  }
}

# Associate the Route Table with the first public Subnet
resource "aws_route_table_association" "html_app_route_table_association1" {
  subnet_id      = aws_subnet.html_app_subnet1.id
  route_table_id = aws_route_table.html_app_route_table.id
}

# Associate the Route Table with the second public Subnet
resource "aws_route_table_association" "html_app_route_table_association2" {
  subnet_id      = aws_subnet.html_app_subnet2.id
  route_table_id = aws_route_table.html_app_route_table.id
}

# Create a Security Group
resource "aws_security_group" "html_app_sg" {
  vpc_id = aws_vpc.html_app_vpc.id
  name   = "html-app-sg"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allow HTTP traffic from anywhere
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # Allow all outbound traffic
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "html-app-sg"
  }
}

resource "aws_ecr_repository" "html_app" {
  name = var.ecr_repo_name
}

// Creating an S3 bucket for the storing of artifacts 
resource "aws_s3_bucket" "pipeline_artifacts" {
  bucket = "simple-html-app-pipeline-artifacts"
}


// Creating the ECS cluster for the Deployment 
resource "aws_ecs_cluster" "html_app_cluster" {
  name = var.ecs_cluster_name
}

resource "aws_ecs_task_definition" "html_app_task" {
  family                   = var.ecs_task_definition_name
  requires_compatibilities = ["FARGATE"]
  network_mode            = "awsvpc"
  memory                  = "512"
  cpu                     = "256"

  execution_role_arn      = aws_iam_role.ecs_task_execution_role.arn  # Add this line

  container_definitions = jsonencode([{
    name      = "html-app-container"
    image     = "${aws_ecr_repository.html_app.repository_url}:latest"
    essential = true
    portMappings = [{
      containerPort = 80
      hostPort     = 80
    }]
  }])
}


resource "aws_ecs_service" "simple_html_service" {
  name            = var.ecs_service_name
  cluster         = aws_ecs_cluster.html_app_cluster.id
  task_definition = aws_ecs_task_definition.html_app_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.html_app_subnet1.id]
    security_groups  = [aws_security_group.html_app_sg.id]
    assign_public_ip = true
  }
}
