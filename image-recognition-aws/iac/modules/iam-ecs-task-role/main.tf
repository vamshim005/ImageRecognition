// IAM ECS Task Role module (from terraform-aws-modules/iam/aws v5.34.0)

resource "aws_iam_role" "this" {
  name = var.name
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "this" {
  for_each = var.policies
  name     = each.key
  role     = aws_iam_role.this.id
  policy   = each.value
} 