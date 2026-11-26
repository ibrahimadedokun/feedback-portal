# AWS static frontend hosting

This Terraform environment provisions a private S3 bucket, a signed CloudFront origin, a CloudFront distribution, its required dedicated WAF web ACL, a CloudFront Free subscription, and a GitHub OIDC role for publishing. No application server or container runs in AWS.

## Prerequisites

Use Terraform 1.7+ and an AWS provisioning identity authorized to manage S3, CloudFront, WAF, IAM/OIDC, and Pricing Plan Manager subscriptions. The AWS provider is locked to a version that supports aws_pricingplanmanager_subscription.

CloudFront flat-rate plans require an eligible account; accounts using the AWS Free Tier account plan are excluded by [AWS's eligibility rules](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/flat-rate-pricing-plan.html). The subscription is explicitly FREE with no paid fallback. Its dedicated WAF ACL is required for eligibility; no custom filtering rules or paid logging are configured.

The Free plan's published allowances include 1 million requests, 100 GB transfer, and S3 storage credits. S3 operations and services outside the plan can still be charged. Creation starts with separate resources before subscription activation: verify cloudfront_plan_status is ACTIVE before relying on coverage. A failed subscription can leave those resources billed at their normal rates. See [CloudFront pricing](https://aws.amazon.com/cloudfront/pricing/).

## Configure and provision

Set the public HTTPS API URL in [public/config.js](../public/config.js) before publishing. The browser calls the external API directly. Configure the API's CORS policy for the frontend hostname.

From this directory, copy terraform.tfvars.example to terraform.tfvars. Set github_repository, aws_region, and github_branch. The workflow deploys develop; its trigger and github_branch must match. Set github_repository_ids if the repository uses immutable OIDC subjects. The WAF ACL is created through a provider alias in us-east-1, independently of the S3 region.

```powershell
terraform init
terraform fmt -check
terraform validate
terraform test
terraform plan -out=hosting.tfplan
terraform apply hosting.tfplan
terraform output -raw application_url
terraform output -raw cloudfront_plan_status
terraform output -json github_actions_variables
```

terraform test uses mocked providers and creates no cloud resources. Review the saved plan before applying. Terraform provisions infrastructure only; publish public/ next, otherwise the new bucket has no index.html. S3 public access is blocked, object ACLs are disabled, and its bucket policy permits reads only from this CloudFront distribution through Origin Access Control.

If the account already has a GitHub OIDC provider managed elsewhere, import that provider into this state or adapt the configuration to reference the existing provider before applying. Do not create a duplicate provider URL.

## Publish from GitHub Actions

Configure the repository settings below:

| Setting | Kind | Terraform value |
| --- | --- | --- |
| AWS_ROLE_ARN | Secret | github_actions_role_arn output |
| AWS_REGION | Variable | github_actions_variables.AWS_REGION |
| WEBSITE_BUCKET | Variable | github_actions_variables.WEBSITE_BUCKET |
| CLOUDFRONT_DISTRIBUTION_ID | Variable | github_actions_variables.CLOUDFRONT_DISTRIBUTION_ID |
| AWS_APPLICATION_URL | Variable | github_actions_variables.AWS_APPLICATION_URL |

Run **Deploy to AWS Static Hosting** on develop or push to develop. The workflow validates and tests Terraform with mocks, runs desktop/mobile browser tests, assumes the deployment role, syncs public/ to the bucket, deletes stale assets, invalidates the CDN cache, and checks the live index and project list. API requests remain mocked in browser tests; verify real message delivery separately.

The deployment role can publish only to this bucket and refresh this distribution. It has no compute, application-environment, or infrastructure-provisioning permissions. Assets use a five-minute cache lifetime; deployment waits for cache invalidation before checking the frontend.

## Migrate the previous deployment

Keep the existing state and provider lock file. Remove obsolete environment_name, instance_type, vpc_id, and subnet_ids inputs from local tfvars or CI variable sets. The current example lists all supported inputs.

The migration plan removes the Beanstalk application/environment and versions, compute/service roles and instance profile, deployment-artifact bucket and contents, and obsolete release lifecycle configuration. The existing CloudFront resource address remains, allowing an in-place origin change; verify the actual plan preserves the distribution and hostname.

Applying switches the origin to a new bucket that is empty until publication, so schedule the cutover and run the static deployment immediately afterward. Update GitHub settings before publishing. Remove old EB_APPLICATION_NAME, EB_ENVIRONMENT_NAME, and DEPLOYMENT_BUCKET variables. No resources from the separately hosted API belong in this state.

Provisioning is not performed by the deployment workflow. A configuration change alone does not remove the old billable infrastructure; that happens when you explicitly apply the reviewed migration plan.

## State, updates, and removal

Keep Terraform state and saved plans private and backed up. The old archive/random provider requirements have been removed; initializing refreshes the lock selections. If an older state still needs those providers to destroy legacy resources, let terraform init install them during migration and run it again after applying to prune unused selections.

When changing provider versions, refresh checksums with terraform providers lock -platform=windows_amd64 -platform=linux_amd64 and commit the lock file. CI initializes with -lockfile=readonly.

For removal, disable automatic publishing and empty only the website bucket, then review terraform plan -destroy and run terraform destroy. The bucket deliberately has no force_destroy setting. The subscription depends on the distribution and ACL, so Terraform cancels the subscription before deleting them. External API resources are unaffected.
