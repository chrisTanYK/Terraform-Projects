# Terraform provider configuration
provider "aws" {
  region = "us-east-1" # Set your preferred region
}

# Generate SSH key pair
resource "tls_private_key" "christanyk" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Save private key to local file
resource "local_file" "private_key" {
  content  = tls_private_key.christanyk.private_key_pem
  filename = "./christanyk.pem"

  provisioner "local-exec" {
    command = "chmod 400 ./christanyk.pem"
  }
}

# Create AWS key pair from the generated public key
resource "aws_key_pair" "christanyk_key" {
  key_name   = "christanyk"
  public_key = tls_private_key.christanyk.public_key_openssh
}

# Create a new VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "christanyk-vpc"
  }
}

# Create a public subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "christanyk-public-subnet"
  }
}

# Create an Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "christanyk-igw"
  }
}

# Create a route table for public access
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "christanyk-public-route"
  }
}

# Associate route table with the public subnet
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Create Security Group
resource "aws_security_group" "christanyk_sg" {
  name        = "christanyk-sg"
  description = "Security group for christanyk EC2 instance"
  vpc_id      = aws_vpc.main.id

  # Allow SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS access
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "christanyk-sg"
  }
}

# Data source to get latest Amazon Linux 2023 AMI
data "aws_ami" "latest_amazon_linux" {
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-*"]
  }

  owners = ["amazon"]
}

# Create IAM Policy for DynamoDB (List and Read Access)
resource "aws_iam_policy" "dynamodb_read" {
  name        = "christanyk-dynamodb-read"
  description = "Policy to allow EC2 to read from DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "dynamodb:List*",
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:Query"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}

# Create IAM Role for EC2
resource "aws_iam_role" "ec2_dynamodb_role" {
  name = "christanyk-dynamodb-read-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Attach DynamoDB Policy to IAM Role
resource "aws_iam_policy_attachment" "dynamodb_read_attach" {
  name       = "attach-dynamodb-read"
  policy_arn = aws_iam_policy.dynamodb_read.arn
  roles      = [aws_iam_role.ec2_dynamodb_role.name]
}

# Create IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_dynamodb_profile" {
  name = "christanyk-dynamodb-profile"
  role = aws_iam_role.ec2_dynamodb_role.name
}

# Create DynamoDB Table
resource "aws_dynamodb_table" "bookinventory" {
  name         = "christanyk-bookinventory"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ISBN"
  range_key    = "Genre"

  attribute {
    name = "ISBN"
    type = "S"
  }

  attribute {
    name = "Genre"
    type = "S"
  }

  tags = {
    Name = "bookinventory"
  }
}

# EC2 Instance
resource "aws_instance" "dynamodb_reader" {
  ami                  = data.aws_ami.latest_amazon_linux.id
  instance_type        = "t2.micro"
  subnet_id            = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.christanyk_sg.id]

  key_name = aws_key_pair.christanyk_key.key_name

  iam_instance_profile = aws_iam_instance_profile.ec2_dynamodb_profile.name

  tags = {
    Name = "christanyk-dynamodb-reader"
  }
}

output "ssh_command" {
  value       = "ssh -i ./christanyk.pem ec2-user@${aws_instance.dynamodb_reader.public_ip}"
  description = "Use this command to SSH into the EC2 instance."
}
