resource "aws_codepipeline" "my_pipeline" {
  name     = "my-codepipeline-test"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = "infrasture-backend-test-o56jiz"
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        RepositoryName = "firstcode"
        BranchName     = "master"
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"

      configuration = {
        ProjectName = "terraform-codebuild"
      }
    }
  }
}
