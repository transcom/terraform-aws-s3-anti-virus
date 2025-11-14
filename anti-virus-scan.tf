#
# Anti-Virus Scanning
#

#
# IAM
#

data "aws_iam_policy_document" "assume_role_scan" {
  statement {
    effect = "Allow"

    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "main_scan" {
  # Allow creating and writing CloudWatch logs for Lambda function.
  statement {
    sid = "WriteCloudWatchLogs"

    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.name_scan}:*"]
  }

  statement {
    sid = "s3AntiVirusScan"

    effect = "Allow"

    actions = concat([
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:GetObjectVersion",
      "s3:PutObjectTagging",
      "s3:PutObjectVersionTagging"
    ], var.av_delete_infected_files == "True" ? ["s3:DeleteObject"] : [])

    resources = formatlist("%s/*", data.aws_s3_bucket.main_scan.*.arn)
  }

  statement {
    sid = "s3AntiVirusDefinitions"

    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:GetObjectTagging",
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

  dynamic "statement" {
    for_each = var.kms_key_sns_arn != "" ? [1] : []
    content {
      sid = "kmsGenerateDataKey"

      effect = "Allow"

      actions = [
        "kms:GenerateDataKey",
      ]

      resources = [
        var.kms_key_sns_arn
      ]
    }
  }

  dynamic "statement" {
    for_each = length(compact([var.av_scan_start_sns_arn, var.av_status_sns_arn])) != 0 ? toset([0]) : toset([])

    content {
      sid = "snsPublish"

      actions = [
        "sns:Publish",
      ]

      resources = compact([var.av_scan_start_sns_arn, var.av_status_sns_arn])
    }
  }
}

resource "aws_iam_role" "main_scan" {
  name                 = "lambda-${var.name_scan}"
  assume_role_policy   = data.aws_iam_policy_document.assume_role_scan.json
  permissions_boundary = var.permissions_boundary
  tags                 = var.tags
}

resource "aws_iam_role_policy" "main_scan" {
  name = "lambda-${var.name_scan}"
  role = aws_iam_role.main_scan.id

  policy = data.aws_iam_policy_document.main_scan.json
}

#
# S3 Event
#

data "aws_s3_bucket" "main_scan" {
  count  = length(var.av_scan_buckets)
  bucket = var.av_scan_buckets[count.index]
}

resource "aws_s3_bucket_notification" "main_scan" {
  count  = length(var.av_scan_buckets)
  bucket = element(data.aws_s3_bucket.main_scan.*.id, count.index)

  eventbridge = var.enable_eventbridge

}

#
# CloudWatch Logs
#

resource "aws_cloudwatch_log_group" "main_scan" {
  # This name must match the lambda function name and should not be changed
  name              = "/aws/lambda/${var.name_scan}"
  retention_in_days = var.cloudwatch_logs_retention_days
  kms_key_id        = var.cloudwatch_kms_arn

  tags = merge(
    {
      "Name" = var.name_scan
    },
    var.tags
  )
}