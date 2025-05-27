
data "archive_file" "python_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/python_code"
  output_path = "${path.module}/python_code.zip"
}


## Create Layer for Python requests
resource "aws_lambda_layer_version" "python_requests_layer" {
  filename   = "requests.zip"
  layer_name = "python_layer"

  compatible_runtimes = ["python3.9"]
}

resource "aws_lambda_function" "myLambda" {
  function_name    = "lambda_funct"
  layers           = [aws_lambda_layer_version.python_requests_layer.arn]
  filename         = "${path.module}/python_code.zip"
  handler          = "main.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.python_lambda.output_base64sha256
  role             = aws_iam_role.lambda_role.arn
}


# IAM role which dictates what other AWS services the Lambda function
# may access.
resource "aws_iam_role" "lambda_role" {
  name = "role_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

}


resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

/*
resource "aws_iam_role_policy_attachment" "sqs_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
}
*/

resource "aws_iam_role_policy" "lambda_sqs_policy" {
  name = "lambda-sqs-specific-access"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowSpecificQueueAccess",
        Effect = "Allow",
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ],
        Resource = aws_sqs_queue.terraform_queue.arn
      },
      {
        Sid    = "AllowCloudWatchLogs",
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}



# Attach permissions to allow Lambda to read from S3
resource "aws_iam_policy" "s3_read_policy" {
  name        = "lambda-s3-read-policy"
  description = "Allows Lambda to read objects from S3"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": "${aws_s3_bucket.terraforms3bnaf.arn}/*"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "attach_s3_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.s3_read_policy.arn
}
