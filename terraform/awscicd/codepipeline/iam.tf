resource "aws_iam_role" "codepipeline_role" {
  name = "codepipeline-role-test"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "codepipeline.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codepipeline_policy" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodePipeline_FullAccess"
}

resource "aws_iam_role_policy_attachment" "codepipeline_codecommit_read" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeCommitReadOnly"
}

resource "aws_iam_role_policy" "codepipeline_codecommit_access" {
  name = "CodePipelineCodeCommitAccess"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codecommit:GetBranch",
          "codecommit:GetCommit",
          "codecommit:UploadArchive",
          "codecommit:GetUploadArchiveStatus",
          "codecommit:CancelUploadArchive",
          "codecommit:GitPull"
        ]
        Resource = "arn:aws:codecommit:eu-west-1:${data.aws_caller_identity.current.account_id}:firstcode"
      },
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject"
        ],
        Resource = "arn:aws:s3:::infrasture-backend-test-o56jiz/*"
      },
      {
        Effect = "Allow",
        Action = [
          "s3:ListBucket"
        ],
        Resource = "arn:aws:s3:::infrasture-backend-test-o56jiz"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codepipeline_codebuild_start" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeBuildDeveloperAccess"
}




# Get current AWS account ID for policy reference
data "aws_caller_identity" "current" {}