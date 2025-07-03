
# IAM Role for CodeBuild
resource "aws_iam_role" "codebuild_role" {
  name = "codebuild-terraform-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "codebuild.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# IAM Policy for Terraform + CodeCommit Access
resource "aws_iam_policy" "codebuild_policy" {
  name = "codebuild-terraform-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformPermissions"
        Effect = "Allow"
        Action = [
          "s3:*",
          "dynamodb:*",
          "ec2:*",
          "iam:*",
          "logs:*",
          "cloudwatch:*",
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      },
      {
        Sid    = "CodeCommitReadAccess"
        Effect = "Allow"
        Action = [
          "codecommit:GitPull",
          "codecommit:GetRepository",
          "codecommit:BatchGetRepositories",
          "codecommit:GetBranch"
        ]
        Resource = "arn:aws:codecommit:eu-west-1:${data.aws_caller_identity.current.account_id}:firstcode"
      }
    ]
  })
}

# Get current AWS account ID for policy reference
data "aws_caller_identity" "current" {}

# Attach Policy to Role
resource "aws_iam_role_policy_attachment" "codebuild_role_attach" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = aws_iam_policy.codebuild_policy.arn
}

# CodeBuild Project
resource "aws_codebuild_project" "terraform_build" {
  name          = var.codebuild_project_name
  description   = "Run Terraform from CodeBuild"
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = 10

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = false
  }

  source {
    type      = "CODECOMMIT" # or GITHUB
    location  = "https://git-codecommit.eu-west-1.amazonaws.com/v1/repos/firstcode"
    buildspec = "buildspec.yml"
  }

  logs_config {
    cloudwatch_logs {
      status      = "ENABLED"
      group_name  = "/aws/codebuild/${var.codebuild_project_name}"
      stream_name = "build-log"
    }
  }

  tags = {
    Environment = "Dev"
    Project     = "TerraformPipeline"
  }
}



