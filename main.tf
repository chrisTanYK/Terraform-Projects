provider "aws" {
  region = "us-east-1"  # Change to your preferred AWS region
}

resource "aws_s3_bucket" "example" {
  bucket = "christanyk-s3"  # Change to a unique bucket name

  tags = {
    Name        = "MyTerraformBucket"
    Environment = "Dev"
  }
}

# Enable bucket versioning (Optional)
resource "aws_s3_bucket_versioning" "versioning_example" {
  bucket = aws_s3_bucket.example.id
  versioning_configuration {
    status = "Enabled"
  }
}

# To destroy the bucket, run:
# terraform destroy
