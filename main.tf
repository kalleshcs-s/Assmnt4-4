# --------------------------
# VPCs - one per region (use provider alias)
# --------------------------
resource "aws_vpc" "use1_vpc" {
  provider = aws.use1
  cidr_block = var.vpc_cidr_use1
  tags = {
    Name = "${var.project_name}-vpc-use1"
    Region = "us-east-1"
  }
}

resource "aws_subnet" "use1_subnet" {
  provider = aws.use1
  vpc_id = aws_vpc.use1_vpc.id
  cidr_block = cidrsubnet(var.vpc_cidr_use1, 8, 1)
  availability_zone = "us-east-1a"
  tags = { Name = "${var.project_name}-subnet-use1" }
}

resource "aws_vpc" "usw2_vpc" {
  provider = aws.usw2
  cidr_block = var.vpc_cidr_usw2
  tags = {
    Name = "${var.project_name}-vpc-usw2"
    Region = "us-west-2"
  }
}

resource "aws_subnet" "usw2_subnet" {
  provider = aws.usw2
  vpc_id = aws_vpc.usw2_vpc.id
  cidr_block = cidrsubnet(var.vpc_cidr_usw2, 8, 1)
  availability_zone = "us-west-2a"
  tags = { Name = "${var.project_name}-subnet-usw2" }
}

# --------------------------
# Simple EC2 instances per region (for routing target / testing)
# --------------------------
resource "aws_instance" "web_use1" {
  provider = aws.use1
  ami           = var.ami_us_east_1
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.use1_subnet.id

  tags = {
    Name = "${var.project_name}-web-use1"
    Region = "us-east-1"
  }
}

resource "aws_instance" "web_usw2" {
  provider = aws.usw2
  ami           = var.ami_us_west_2
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.usw2_subnet.id

  tags = {
    Name = "${var.project_name}-web-usw2"
    Region = "us-west-2"
  }
}

# --------------------------
# S3 Buckets (source in us-east-1, destination in us-west-2)
# --------------------------
resource "aws_s3_bucket" "bucket_use1" {
  provider = aws.use1
  bucket   = "${var.project_name}-state-use1-${random_id.use1.hex}"
  acl      = "private"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = { Name = "${var.project_name}-bucket-use1" }
}

resource "aws_s3_bucket" "bucket_usw2" {
  provider = aws.usw2
  bucket   = "${var.project_name}-replica-usw2-${random_id.usw2.hex}"
  acl      = "private"

  versioning { enabled = true }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = { Name = "${var.project_name}-bucket-usw2" }
}

# random_id for bucket uniqueness
resource "random_id" "use1" {
  byte_length = 4
}
resource "random_id" "usw2" {
  byte_length = 4
}

# --------------------------
# IAM role & policy for S3 replication (created in source region)
# --------------------------
data "aws_caller_identity" "current" {
  provider = aws.use1
}

data "aws_iam_policy_document" "replication_role" {
  provider = aws.use1

  statement {
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "s3_replication_role" {
  provider = aws.use1
  name = "${var.project_name}-s3-repl-role"
  assume_role_policy = data.aws_iam_policy_document.replication_role.json
}

data "aws_iam_policy_document" "replication_policy" {
  provider = aws.use1

  statement {
    effect = "Allow"
    actions = [
      "s3:GetReplicationConfiguration",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.bucket_use1.arn
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObjectVersion",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectLegalHold",
      "s3:GetObjectRetention",
      "s3:GetObjectVersionTagging"
    ]
    resources = ["${aws_s3_bucket.bucket_use1.arn}/*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
      "s3:GetObjectVersionTagging"
    ]
    resources = ["${aws_s3_bucket.bucket_usw2.arn}/*"]
  }

  # Allow PutObject on destination bucket
  statement {
    effect = "Allow"
    actions = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.bucket_usw2.arn}/*"]
  }
}

resource "aws_iam_role_policy" "replication_role_policy" {
  provider = aws.use1
  name   = "${var.project_name}-s3-repl-policy"
  role   = aws_iam_role.s3_replication_role.id
  policy = data.aws_iam_policy_document.replication_policy.json
}

# --------------------------
# S3 Replication configuration (source region)
# --------------------------
resource "aws_s3_bucket_replication_configuration" "repl" {
  provider = aws.use1
  bucket = aws_s3_bucket.bucket_use1.id
  role   = aws_iam_role.s3_replication_role.arn

  rules {
    id     = "replicate-all"
    status = "Enabled"
    priority = 1

    filter {
      prefix = ""
    }

    destination {
      bucket        = aws_s3_bucket.bucket_usw2.arn
      storage_class = "STANDARD"
      access_control_translation {
        owner = "Destination"
      }
    }
  }
}

# --------------------------
# Route53 health check and failover records
# --------------------------
resource "aws_route53_health_check" "web_use1_check" {
  provider = aws.use1
  depends_on = [aws_instance.web_use1]

  fqdn              = aws_instance.web_use1.public_dns
  port              = 80
  type              = "HTTP"
  resource_path     = "/"
  request_interval  = 30
  failure_threshold = 3
  tags = { Name = "${var.project_name}-hc-use1" }
}

resource "aws_route53_health_check" "web_usw2_check" {
  provider = aws.usw2
  depends_on = [aws_instance.web_usw2]

  fqdn              = aws_instance.web_usw2.public_dns
  port              = 80
  type              = "HTTP"
  resource_path     = "/"
  request_interval  = 30
  failure_threshold = 3
  tags = { Name = "${var.project_name}-hc-usw2" }
}

# Note: Route53 hosted zone is global; use default provider (primary region)
data "aws_route53_zone" "zone" {
  name         = var.domain_name
  private_zone = false
}

# PRIMARY record in us-east-1
resource "aws_route53_record" "primary" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = 30
  set_identifier = "use1-primary"
  weight         = 100
  failover       = "PRIMARY"

  alias {
    name                   = aws_instance.web_use1.public_dns
    zone_id                = data.aws_route53_zone.zone.zone_id
    evaluate_target_health = true
  }

  health_check_id = aws_route53_health_check.web_use1_check.id
}

# SECONDARY record in us-west-2
resource "aws_route53_record" "secondary" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = 30
  set_identifier = "usw2-secondary"
  weight         = 0
  failover       = "SECONDARY"

  alias {
    name                   = aws_instance.web_usw2.public_dns
    zone_id                = data.aws_route53_zone.zone.zone_id
    evaluate_target_health = true
  }

  health_check_id = aws_route53_health_check.web_usw2_check.id
}

# --------------------------
# Data sharing example: fetch S3 bucket ARNs across providers (cross-region)
# --------------------------
output "bucket_use1_name" {
  value = aws_s3_bucket.bucket_use1.id
}

output "bucket_usw2_name" {
  value = aws_s3_bucket.bucket_usw2.id
}

output "web_use1_public_ip" {
  value = aws_instance.web_use1.public_ip
}

output "web_usw2_public_ip" {
  value = aws_instance.web_usw2.public_ip
}
