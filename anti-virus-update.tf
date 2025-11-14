#
# Anti-Virus Definitions
#

#
# IAM
#

data "aws_iam_policy_document" "assume_role_update" {
  statement {
    effect = "Allow"

    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "main_update" {
  # Allow creating and writing CloudWatch logs for Lambda function.
  statement {
    sid = "WriteCloudWatchLogs"

    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.name_update}:*"]
  }

  statement {
    sid = "s3GetAndPutWithTagging"

    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:PutObjectVersionTagging",
    ]

    resources = ["arn:${data.aws_partition.current.partition}:s3:::${var.av_definition_s3_bucket}/${var.av_definition_s3_prefix}/*"]
  }

  statement {
    sid = "s3HeadObject"

    effect = "Allow"

    actions = [
      "s3:ListBucket",
    ]

    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::${var.av_definition_s3_bucket}",
      "arn:${data.aws_partition.current.partition}:s3:::${var.av_definition_s3_bucket}/*",
    ]
  }
}

resource "aws_iam_role" "main_update" {
  name                 = "lambda-${var.name_update}"
  assume_role_policy   = data.aws_iam_policy_document.assume_role_update.json
  permissions_boundary = var.permissions_boundary
  tags                 = var.tags
}

resource "aws_iam_role_policy" "main_update" {
  name = "lambda-${var.name_update}"
  role = aws_iam_role.main_update.id

  policy = data.aws_iam_policy_document.main_update.json
}

#
# CloudWatch Logs
#

resource "aws_cloudwatch_log_group" "main_update" {
  # This name must match the lambda function name and should not be changed
  name              = "/aws/lambda/${var.name_update}"
  retention_in_days = var.cloudwatch_logs_retention_days
  kms_key_id        = var.cloudwatch_kms_arn

  tags = merge(
    {
      "Name" = var.name_update
    },
    var.tags
  )
}