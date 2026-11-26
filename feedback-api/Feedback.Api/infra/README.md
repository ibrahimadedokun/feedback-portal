# Feedback API on Azure Container Apps

The .NET 10 API runs on **Azure Container Apps Consumption**, using a public image
from **GitHub Container Registry (GHCR)**. It publishes messages to the existing
AWS SNS topic. No App Service plan or Azure Container Registry is required.

## Architecture and costs

- Existing resource group and Log Analytics workspace are reused.
- A Container Apps environment has only the Consumption workload profile.
- The API uses 0.25 vCPU / 0.5 GiB RAM, scales from zero to one replica, and accepts
  HTTPS through public ingress. TLS terminates at ingress; the container listens
  on HTTP port 8080 as a non-root user.
- `/health` supports startup/readiness/liveness checks. HTTP requests wake the app
  after it scales to zero; the first request can be slower.
- GHCR stores the public compiled application image. AWS keys are injected through
  Container Apps secrets at runtime and are not included in the image or workflow.
- The existing least-privilege AWS IAM user/key and SNS publish policy are retained.
- Unused Application Insights from the earlier App Service deployment is removed.
  Application console/system logs are collected in Log Analytics instead.

Consumption has a monthly free allocation of 180,000 vCPU-seconds, 360,000
GiB-seconds and 2 million requests per subscription. Exceeding any allowance can
incur charges; it is not a hard spending cap. Log ingestion, SNS delivery and
network transfer are billed separately. The workspace has a 0.1 GB/day ingestion
cap to limit log volume; this is not an exact billing ceiling and logs may be
unavailable after the cap is reached. There is no paid ACR registry.

See [Container Apps pricing](https://azure.microsoft.com/pricing/details/container-apps/)
and [GHCR documentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).

## Publish the image on GitHub

The repository is `ibrahimadedokun/feedback-portal`. The solution lives at
`feedback-api/Feedback.Api`; the workflow belongs at the repository root:
`.github/workflows/api-container.yml` (not inside the solution directory).
The copy supplied with this solution must be placed there when integrating it.

1. Push the API and workflow to `main`, or run **Build Feedback API image** manually.
2. The workflow builds Linux amd64 from the Dockerfile, starts the image, checks
   `/health` and empty-message validation, then publishes with `GITHUB_TOKEN`.
   Pull requests build and test without pushing images.
3. Open your GitHub profile's Packages page, select `feedback-api`, then Package
   settings and set visibility to **Public**. New GHCR packages default to private,
   even when the source repository is public. Public pulls require no PAT.
4. Copy `ghcr.io/ibrahimadedokun/feedback-api:sha-<full-commit-sha>` from the run.
   Prefer pinning the returned digest for deployments. `latest` is also published
   for convenience; deployments should use a commit tag or digest.

The workflow needs `contents: read` and `packages: write`, defined in the YAML.
No Azure or AWS credentials are needed by the image build. Ensure Actions and
package publishing are enabled for the repository.

## Deploy infrastructure and API

Prerequisites:

- Terraform >= 1.17 with the locked AzureRM/AWS/random providers.
- Azure CLI logged in to the target subscription with resource creation rights.
- AWS credentials permitted to read the SNS topic and manage its dedicated IAM user.
- A successful GHCR build whose image is public and includes Linux amd64.

From the solution directory, create `infra/terraform.tfvars` using the example,
then fill in your subscription, region and topic. Keep this file local.

```powershell
Copy-Item infra/terraform.tfvars.example infra/terraform.tfvars
./infra/Deploy.ps1 -Image 'ghcr.io/ibrahimadedokun/feedback-api:sha-<full-commit-sha>'
```

`Deploy.ps1` persists the selected image in the ignored
`infra/deployment.auto.tfvars.json`, initializes and validates Terraform, saves a
plan, then applies it. It stops on errors. Future applies use that persisted image.
Review the saved plan before applying manually when changing production resources.

Manual equivalent:

```powershell
terraform '-chdir=infra' init
terraform '-chdir=infra' plan '-out=container-apps.tfplan'
terraform '-chdir=infra' apply container-apps.tfplan
$url = terraform '-chdir=infra' output -raw container_app_url
Invoke-RestMethod "$url/health"
```

To verify SNS end to end, send a real test message (this notifies topic subscribers):

```powershell
Invoke-RestMethod -Method Post -Uri "$url/messages" -ContentType 'application/json' `
  -Body '{"message":"Container Apps deployment smoke test","subject":"Smoke test"}'
```

A successful response contains `messageId`. An empty message returns HTTP 400.
OpenAPI is available only in Development. `/messages` is currently unauthenticated;
restrict or add authentication before using it as a private publishing endpoint.

## Local development and Docker

The .NET 10 SDK is needed for local builds. No AWS credentials are stored in
`appsettings.json`; set user secrets from the project directory:

```powershell
cd Feedback.Api
dotnet user-secrets set 'AWS:AccessKeyId' '<access-key-id>'
dotnet user-secrets set 'AWS:SecretAccessKey' '<secret-access-key>'
dotnet user-secrets set 'AWS:Region' 'eu-west-2'
dotnet user-secrets set 'Sns:TopicArn' '<topic-arn>'
dotnet run
```

From the solution directory, `docker build -t feedback-api .` builds the image.
Supply `AWS__Region`, `AWS__AccessKeyId`, `AWS__SecretAccessKey` and `Sns__TopicArn`
using a local env file outside the build context, then run:

```powershell
docker run --rm -p 8080:8080 --env-file <private-env-file> feedback-api
```

The Docker context allowlist excludes Terraform state, tfvars, IDE settings,
build artifacts and local environment files.

## State, migration and troubleshooting

- State and saved plans contain the AWS secret key. Keep them out of Git and use
  an access-restricted remote backend beyond a sandbox (see `versions.tf`).
- The old App Service resources were never successfully created. Applying this
  configuration creates Container Apps and deletes only unused Application Insights;
  it preserves the resource group, Log Analytics, suffix and AWS credentials.
- Outputs are now `container_app_name`, `container_app_url`, `container_image`,
  `resource_group_name` and `sns_topic_arn`; old `web_app_*` outputs are removed.
- Image pull errors: confirm GHCR package visibility is Public and that the exact
  digest/tag exists with a Linux amd64 image.
- Container Apps uses Microsoft.App quotas, separate from Microsoft.Web. If the
  environment creation is rejected, inspect the exact region/subscription quota.
- Rotate the deployed AWS key with
  `terraform '-chdir=infra' apply '-replace=aws_iam_access_key.feedback_api'`.
- For logs, run `az containerapp logs show -g <resource-group> -n <app> --follow`.

