data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/package"
  output_path = "${path.module}/package.zip"
}

resource "aws_lambda_function" "http_api_lambda" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.name_prefix}-topmovies-api"
  description      = "Lambda function to write to dynamodb"
  runtime          = "python3.13"
  handler          = "app.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  role             = aws_iam_role.lambda_exec.arn

  environment {
    variables = {DDB_TABLE = aws_dynamodb_table.table.name} # todo: fill with apporpriate value
  }
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.http_api_lambda.function_name}"
  retention_in_days = 7 # Set log retention to 7 days

  # Ensures log group is created after the Lambda function
  depends_on = [aws_lambda_function.http_api_lambda]
}

resource "aws_iam_role" "lambda_exec" {
  name = "${local.name_prefix}-topmovies-api-executionrole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_exec_role" {
  name = "${local.name_prefix}-topmovies-api-ddbaccess"

  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:DeleteItem"
            ],
            "Resource": "${aws_dynamodb_table.table.arn}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_exec_role.arn
}

# Attach AWS managed policy for basic Lambda execution
/*resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}*/

resource "aws_cloudwatch_log_metric_filter" "info_count" {
  name           = "info-count"
  log_group_name = aws_cloudwatch_log_group.lambda_log_group.name # Replace with the name of your CloudWatch log group

  pattern = "[INFO]" # The filter pattern to match "[INFO]"

  metric_transformation {
    name      = "info-count"
    namespace = "/moviedb-api/xinwei"
    value     = "1"
    unit      = "None"
  }
}

# Create the SNS topic
resource "aws_sns_topic" "cloudwatch_alarm_topic" {
  name = "${local.name_prefix}_cloudwatch_alarm_topic"
}

# Subscribe the email endpoint to the SNS topic
resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.cloudwatch_alarm_topic.arn
  protocol  = "email"
  endpoint  = "xinwei.cheng.88@gmail.com"
}

# Create the CloudWatch Alarm
resource "aws_cloudwatch_metric_alarm" "info_count_breach_alarm" {
  alarm_name          = "${local.name_prefix}-info-count-breach"
  comparison_operator = "GreaterThanThreshold" # Trigger when value is greater than threshold
  evaluation_periods  = 1                      # Number of periods to evaluate
  metric_name         = "info-count"
  namespace           = aws_cloudwatch_log_metric_filter.info_count.metric_transformation[0].namespace # Replace <alias> with your desired namespace alias
  period              = 60                     # 1 minute (in seconds)
  statistic           = "Sum"                  # Sum statistic
  threshold           = 10                     # Static threshold

  # Send notification to SNS topic
  alarm_actions = [
    aws_sns_topic.cloudwatch_alarm_topic.arn
  ]
}
