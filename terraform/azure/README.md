# Azure deployment

This is an independent Terraform deployment of the existing Node.js 26 app to
Azure Container Apps. Run every Terraform command below from `terraform/azure`;
the parent directory contains a separate AWS deployment and state.

## Cost choices

- **Consumption only:** 0.25 vCPU, 0.5 GiB RAM, zero minimum replicas, one maximum
  replica, and a single active revision. Idle apps scale to zero; the first visit
  after idling can be slow. Revision changes can briefly run both revisions.
- **Public GHCR image:** no Azure Container Registry with a recurring fee.
  The image includes application source and public project configuration. Use
  this option only if those files can be public. The Docker build uses an
  allowlist, excluding `.env`, credentials, Terraform state, and development files.
- **Managed HTTPS:** an `azurecontainerapps.io` hostname and platform TLS, without
  a purchased domain, gateway, or separately managed certificate.
- **No database, dedicated workload profile, NAT Gateway, private endpoints,
  Log Analytics workspace, or Application Insights.** Logs can be streamed but
  are not retained in a paid logging workspace.

[Container Apps Consumption pricing](https://azure.microsoft.com/pricing/details/container-apps/)
currently includes 180,000 vCPU-seconds, 360,000 GiB-seconds and two million HTTP
requests per subscription per month. These allowances are shared with other apps.
Excess usage and applicable outbound data transfer are billed. One maximum replica
limits concurrency and compute exposure; it is not a spending cap. Cold starts,
deployment activity, and sustained traffic still consume resources.

[App Service F1](https://azure.microsoft.com/pricing/details/app-service/linux/)
offers free shared hosting with 60 CPU minutes per day. Container Apps is used
here to preserve the app's Node.js 26 runtime in a container and allow idle
scale to zero without depending on the App Service managed runtime catalogue.

Demo mode does not deliver or store feedback. Real delivery continues through
the existing AWS SNS integration and may incur AWS SNS charges. This deployment
does not create an Azure email service or migrate existing AWS resources.

## Prerequisites

1. Terraform 1.5+, Azure CLI, and an Azure subscription. The bootstrap identity
   must be able to create resources and role assignments in the subscription
   (for example Contributor plus Role Based Access Control Administrator).
2. A GitHub repository containing these files, with Actions and GHCR publishing
   enabled. The deployment workflow uses the `main` branch.
3. A GitHub Actions environment named **azure-production**. Restrict its
   deployment branches to `main` in the environment settings.
4. If using SNS, an existing topic, confirmed subscriptions, and AWS credentials
   with only `sns:Publish` on that topic. An Azure identity alone does not grant
   AWS permissions.

## Publish the first image

1. Commit and push these files to GitHub.
2. Run **Actions → Deploy to Azure Container Apps → Run workflow** on `main`,
   leaving **Deploy after publishing** off. This runs backend/browser tests,
   builds the production image, smoke tests it, and publishes to GHCR. It needs
   no Azure credentials for this first build.
3. Copy the image reference from the workflow summary. The tag contains the
   commit SHA and run attempt.
4. In GitHub, open the package's **Package settings → Change visibility** and
   make it **Public**. New GHCR packages default to private even for public
   repositories. Azure pulls this image anonymously. See
   [GitHub's container registry guide](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).

The workflow pushes only the tested `linux/amd64` image. Docker's
[`push --platform` option](https://docs.docker.com/reference/cli/docker/image/push/)
publishes that platform's manifest without an image index or build attestations.
This avoids the index/attestation publication path when GHCR accepts image
layers but rejects the final push. Build attestations are not published by this
workflow.

If GHCR reports a package permission error, open the existing package's
**Package settings → Manage Actions access** and grant this repository **Write**
access. The workflow already requests `packages: write`; an existing package
can still require an explicit repository grant. Making a package public grants
anonymous pull access, not publishing permission. See
[GitHub's package access settings](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility).

## Provision Azure

In PowerShell, from the repository root:

```powershell
az login
az account set --subscription YOUR_SUBSCRIPTION_ID
az account show --query '{subscription:id,tenant:tenantId}'

Set-Location terraform/azure
Copy-Item terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`: set `subscription_id`, `container_image`, and the exact
`github_oidc_subject`. The default region is `uksouth`; change it if the
subscription lacks regional Consumption capacity. Names must be unique within
their Azure scopes; use a different `project_name` if necessary.

The OIDC subject must match the token GitHub issues to the **azure-production**
environment. For repositories using legacy subjects:

```text
repo:OWNER/REPOSITORY:environment:azure-production
```

For repositories using GitHub's immutable subjects, include owner and repository
IDs in the exact format configured by GitHub:

```text
repo:OWNER@OWNER_ID/REPOSITORY@REPOSITORY_ID:environment:azure-production
```

Repositories created after
July 15, 2026 use immutable subjects by default. Check
[GitHub's subject documentation](https://docs.github.com/en/actions/reference/security/oidc#immutable-subject-claims)
and your repository's OIDC configuration before applying. A mismatched subject
prevents Azure login. No client secret is required.

The default `feedback_mode = "demo"` is ready to deploy without AWS credentials.
For real delivery, set `feedback_mode = "sns"` and `sns_topic_arn`. Supply the
following sensitive Terraform variable using your secret manager or local
environment, rather than committing it to a file:

```powershell
# Placeholder values only: replace locally through your secure credential flow.
$env:TF_VAR_aws_credentials = '{"access_key_id":"REPLACE","secret_access_key":"REPLACE"}'
# Temporary credentials also require a session_token property and expire.
```

If you already use AWS CLI v2, load its resolved credentials in the same
PowerShell session instead of copying keys manually:

```powershell
.\Set-AwsCredentials.ps1
# Or select a named profile:
# .\Set-AwsCredentials.ps1 -Profile YOUR_PROFILE
terraform plan -out=deployment.tfplan
```

The helper uses [AWS CLI credential export](https://docs.aws.amazon.com/cli/latest/reference/configure/export-credentials.html)
and includes the session token when present. Authenticate your profile first.
Terraform does not automatically read AWS CLI profiles or `AWS_ACCESS_KEY_ID`
into `aws_credentials`: this Azure deployment needs the explicit Terraform input
to populate the container's secrets. A valid topic ARN alone is insufficient.
Temporary credentials expire inside the deployed container too; refresh the
credentials and apply again before expiry. The preconditions check input format
and presence, not whether AWS grants `sns:Publish` permission.

These values are stored as Azure Container Apps secrets and referenced by server
environment variables. Terraform also records their plaintext values in state;
keep state private and backed up. For team use, configure an access-controlled
Azure Storage backend with locking before applying; its storage is separately
billed. The default local state is Git-ignored. Rotate AWS credentials as needed
and apply again; no AWS keys are passed through GitHub Actions.

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan -out=deployment.tfplan
terraform apply deployment.tfplan
terraform output -raw application_url
terraform output -json github_actions_variables
```

The committed provider lock file includes checksums for Windows AMD64 (local
development) and Linux AMD64 (GitHub Actions). After changing provider versions,
refresh both platform checksums before committing:

```powershell
terraform providers lock -platform=windows_amd64 -platform=linux_amd64
```

CI uses `terraform init -lockfile=readonly`, so missing Linux checksums can cause
the following `terraform validate` step to reject the cached provider. Commit
the updated `.terraform.lock.hcl` and start a new workflow run on that commit;
rerunning an older workflow run still uses its original commit and lock file.

The plan creates a resource group, Consumption environment, container app, and a
user-assigned identity with an environment-scoped GitHub federation credential.
The identity receives **Container Apps Contributor** on this app only. Terraform
can register required Azure resource providers; allow time for initial provider
registration and role propagation. Review the plan before applying.

Plan files contain secrets too; delete the saved plan after applying:

```powershell
Remove-Item -LiteralPath deployment.tfplan
Remove-Item Env:TF_VAR_aws_credentials -ErrorAction SilentlyContinue
```

## Enable subsequent deployments

Add the values from `github_actions_variables` as GitHub Actions repository
variables. The `AZURE_DEPLOY_ENABLED` flag must be a repository variable so it is
available before the deployment environment is entered:

| Variable | Purpose |
| --- | --- |
| `AZURE_CLIENT_ID` | Terraform-created deployment identity client ID |
| `AZURE_TENANT_ID` | Azure tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Deployment subscription |
| `AZURE_RESOURCE_GROUP` | Terraform-created resource group |
| `AZURE_CONTAINER_APP` | Terraform-created container app name |
| `AZURE_DEPLOY_ENABLED` | `true` to deploy on pushes to `main` |

Run the workflow with **Deploy after publishing** enabled on `main`, or push a
new commit to `main`. It checks tests and the production container before
publishing, checks anonymous image access, exchanges GitHub OIDC for Azure
credentials, updates the image, then checks `/api/config` over HTTPS. Missing
configuration fails before Azure login. The existing AWS workflow has its own
trigger; if AWS deployment is no longer wanted, disable that workflow in GitHub.

Application releases are owned by Actions. Terraform ignores image changes to
avoid reverting a deployed release on the next infrastructure apply. Keep
`container_image` updated to a known good release for recreation. For a rollback,
use a previously published image:

```powershell
az containerapp update --resource-group feedback-portal-azure --name feedback-portal --image ghcr.io/owner/repository:PREVIOUS_TAG --output none
```

Use your configured names. Keep deployed and rollback image tags when cleaning
GHCR packages; scale-from-zero needs access to the referenced image.

## Verify and clean up

Open the `application_url`. `/api/config` should return project metadata and the
configured delivery mode. In demo mode the UI explicitly states submissions are
not delivered. In SNS mode submit a test and confirm receipt at the subscriber;
an API success means SNS accepted the message, not that email arrived. The
deployment smoke check does not send feedback.

The application's rate limiter is process-local and sees the proxy connection
IP. It may group visitors, and resets during restarts and scale to zero. This
configuration is suited to light traffic; shared limiting and retained
monitoring require additional services if needed.

Inspect live logs with:

```powershell
az containerapp logs show --resource-group feedback-portal-azure --name feedback-portal --follow
```

To remove only this Azure deployment, run from `terraform/azure`:

```powershell
terraform plan -destroy
terraform destroy
```

This removes the app, environment, deployment identity, federation, role
assignment and resource group. It leaves AWS resources, GHCR packages, GitHub
settings, and any separately configured remote state storage in place. Disable
the Azure workflow before destroying to avoid releases racing with deletion.
