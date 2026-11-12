# AWS deployment

This Terraform configuration deploys the existing Node.js application to a
single-instance AWS Elastic Beanstalk environment. It creates a private S3
deployment-bundle bucket, narrowly scoped IAM roles, and
a GitHub Actions OIDC role. The first application bundle is deployed by
Terraform; later pushes to `main` are deployed by GitHub Actions.

Feedback is published to your existing standard SNS topic. Terraform does not
create or manage the topic or its email subscriptions. Set `sns_topic_arn` to
its ARN; the application receives permission to publish only to that topic.

The application runs on Node.js 26 on Amazon Linux 2023. Provider versions are
recorded in `.terraform.lock.hcl`; this configuration uses AWS provider 6.x.
When upgrading an existing checkout, run `terraform init -upgrade` and review
`terraform plan` before applying the provider and platform changes.

## Cost and availability

Elastic Beanstalk has no separate service fee, but the AWS resources it creates
are billed. This configuration deliberately uses one `t3.micro` EC2 instance,
small root storage, and no load balancer, NAT Gateway, database, or custom
domain. A single instance is not highly available and can be interrupted during
maintenance or fail without an automatic replacement across multiple
availability zones.

There is no universally free always-on option for this existing server
configuration. The instance, its public IPv4 address, storage, data transfer,
and SNS usage can incur charges. Whether Free Tier benefits or account credits
cover them depends on your account, plan, region, and current AWS offers. Check
the [AWS Free Tier terms](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier.html)
and [Elastic Beanstalk pricing](https://aws.amazon.com/elasticbeanstalk/pricing/)
before applying. Configure an AWS Budget or billing alert first. The lowest-cost
way to stop ongoing environment charges when you are done testing is
`terraform destroy`.

The default Elastic Beanstalk URL is HTTP. Do not send sensitive information
over it. Adding HTTPS with an Application Load Balancer or a separate HTTPS
front end increases cost and is left out of this low-cost setup.

## Prerequisites

1. An AWS account with permissions to create Elastic Beanstalk environments,
   EC2/IAM/S3 resources, and an IAM OIDC provider.
2. Terraform 1.5 or later, AWS CLI v2, and Git installed locally.
3. AWS credentials configured locally through AWS IAM Identity Center/SSO or
   another supported AWS credential provider. Do not put access keys in
   `terraform.tfvars` or GitHub.
4. A GitHub repository containing this project. The workflow below assumes the
   `main` branch.
5. An existing standard SNS topic with your email subscription confirmed.

Elastic Beanstalk uses the account's default VPC if one exists. If it does not,
provide a VPC and subnet IDs in `terraform.tfvars`. The instance needs a public
route so the application can be reached directly without a load balancer.

## Deploy the infrastructure

Run these commands from the repository root in PowerShell:

```powershell
aws configure sso
aws sso login --profile YOUR_PROFILE
$env:AWS_PROFILE = "YOUR_PROFILE"
aws sts get-caller-identity

Copy-Item terraform\terraform.tfvars.example terraform\terraform.tfvars
```

Edit `terraform\terraform.tfvars` and set `github_repository` to the exact
`OWNER/REPOSITORY` value. Set `sns_topic_arn` to your existing topic ARN and
remove any old `feedback_email` setting. Choose `aws_region` for the application
infrastructure; the server's SNS region is read from the topic ARN, so the topic
can be in a different region. For a topic in another AWS account, its owner must
also allow the application's IAM role to publish in the topic's access policy.

If the account has no default VPC, set `vpc_id` and `subnet_ids` to public
subnets in that VPC. Do not include private-only subnets unless you also design
and pay for outbound networking.

Review the plan, then create the resources:

```powershell
Set-Location terraform
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

Review the plan carefully before approving `terraform apply`. It creates
billable resources. The application URL can be retrieved with:

```powershell
terraform output -raw application_url
```

The environment is initially deployed from the repository bundle by Terraform.
You can open the URL and check `GET /api/config` before configuring automatic
deployments.

## Enable GitHub Actions deployments

The Terraform-created IAM role trusts only the configured repository and
branch. It uses GitHub's OIDC token exchange; no long-lived AWS access key is
needed in GitHub.

The deployment policy includes access to upload and read `releases/*`, create
`github-*` application versions, update this environment's CloudFormation stack
and Auto Scaling group, inspect infrastructure, and pass only this project's
service and instance roles to AWS services. Beanstalk also requires access to
its regional `elasticbeanstalk-REGION-ACCOUNT_ID` S3 bucket to stage environment
data, even though release bundles use a separate bucket. The policy covers
that bucket's creation, access controls, and objects. These permissions support
application deployments to the existing environment; infrastructure changes
continue to be managed through Terraform.

For repositories using [immutable OIDC subjects](https://docs.github.com/en/actions/reference/security/oidc#immutable-subject-claims),
set `github_repository_ids` in `terraform.tfvars` before applying. GitHub uses
this format by default for repositories created after July 15, 2026. Retrieve
`owner.id` and `id` from `https://api.github.com/repos/OWNER/REPOSITORY`:

```hcl
github_repository_ids = {
  owner_id      = "123456"
  repository_id = "456789"
}
```

Leave this variable unset only when the repository uses the legacy subject
without IDs. An incorrect subject causes `Not authorized to perform
sts:AssumeRoleWithWebIdentity`. Apply the Terraform change before retrying the
workflow, and ensure `AWS_ROLE_ARN` matches the deployment role output. Manual
workflow runs must select the configured `github_branch`.

1. From the `terraform` directory, copy the output values:

   ```powershell
   terraform output -raw github_actions_role_arn
   terraform output -raw artifact_bucket_name
   terraform output -raw application_name
   terraform output -raw environment_name
   ```

2. In GitHub, open **Settings → Secrets and variables → Actions**.
3. Add the repository **secret** `AWS_ROLE_ARN` using the
   `github_actions_role_arn` output.
4. Add these repository **variables** using the corresponding outputs:
   - `AWS_REGION`: the region in `terraform.tfvars`
   - `DEPLOYMENT_BUCKET`: `artifact_bucket_name`
   - `EB_APPLICATION_NAME`: `application_name`
   - `EB_ENVIRONMENT_NAME`: `environment_name`
5. Push a commit to `main`, or run **Actions → Deploy to AWS Elastic
   Beanstalk → Run workflow**. The workflow installs dependencies and runs
   backend and desktop/mobile browser tests, then packages the app, uploads it to
   private S3, creates a Beanstalk application version, and waits for the
   environment update to finish.

If Terraform reports that the GitHub OIDC provider already exists in this AWS
account, import it into this state before applying:

```powershell
terraform import aws_iam_openid_connect_provider.github arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com
```

Replace `ACCOUNT_ID` with the account ID from `aws sts get-caller-identity`.
If using a non-standard AWS partition, use that partition in the ARN.

## Verify the app

1. Open the `application_url` output in a browser. The feedback page should
   load from the Node.js server.
2. Request `/api/config` on the same host. It should return the projects from
   `projects.json` and `"mode":"sns"`.
3. Check that your existing topic's email subscription is confirmed.
4. Submit test feedback only after confirming the SNS subscription and
   understanding where the feedback will be delivered. SNS accepts messages
   even when no email subscription is confirmed.
5. Check the latest GitHub Actions run and the Elastic Beanstalk environment
   health in the AWS console.

## Update and clean up

Push application changes to `main`; GitHub Actions deploys each revision.
Infrastructure changes are managed separately from the `terraform` directory
with `terraform plan` and `terraform apply`.

To delete the environment and the resources Terraform created:

```powershell
Set-Location terraform
terraform destroy
```

This removes the S3 deployment artifacts along with the application. Your
existing SNS topic and subscriptions remain outside this configuration. Keep the
Terraform state file private and backed up; it records resource identifiers
and configuration.

If you previously applied the configuration that created SNS resources, remove
them from Terraform state before applying this version to preserve them:

```powershell
terraform state rm 'aws_sns_topic_subscription.feedback_email[0]'
terraform state rm 'aws_sns_topic.feedback'
```

Run only the commands for resources present in `terraform state list`, and set
`sns_topic_arn` to the topic you want to keep using. Review the plan to confirm
that it does not delete any SNS resources.
