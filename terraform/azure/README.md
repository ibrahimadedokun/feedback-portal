# Azure Static Web Apps Free

This Terraform environment creates a resource group and an Azure Static Web App with both sku_tier and sku_size set to Free. It publishes public/ directly, with no container app, container registry, deployment identity, or server runtime.

## Configure and provision

Use Terraform 1.7+, Azure CLI, and an identity authorized to manage the resource group and Microsoft.Web/staticSites resources. Set the public HTTPS API URL in [public/config.js](../../public/config.js) before publishing; configure the external API's CORS policy for the frontend origin.

From terraform/azure, copy terraform.tfvars.example to terraform.tfvars. Set subscription_id and optionally project_name. location is the resource group region and defaults to uksouth. site_location defaults to westeurope, which supports Static Web Apps. Keep an existing resource group's location unchanged when migrating.

Region availability also depends on the subscription. If Azure rejects a region with RequestDisallowedByAzure, choose another supported site_location. This deployment uses eastus2 because West Europe rejected new customers; the override is saved in the local terraform.tfvars.

```powershell
az login
az account set --subscription YOUR_SUBSCRIPTION_ID
terraform init
terraform fmt -check
terraform validate
terraform test
terraform plan -out=hosting.tfplan
terraform apply hosting.tfplan
terraform output -raw application_url
terraform output -json github_actions_variables
```

terraform test uses a mocked Azure provider and does not create cloud resources. Review the saved plan before applying. Terraform provisions hosting only; upload frontend files through the workflow after provisioning. The Static Web App provides its own HTTPS hostname.

The [Free plan](https://azure.microsoft.com/en-us/pricing/details/app-service/static/) has storage and bandwidth quotas and no uptime SLA. The separately hosted API, domain purchases, and CI usage have their own costs.

## Configure GitHub Actions

Create a GitHub environment named azure-production and restrict its deployment branch to main. Set:

| Setting | Scope and kind | Value |
| --- | --- | --- |
| AZURE_STATIC_WEB_APPS_API_TOKEN | azure-production environment secret | deployment_token output |
| AZURE_APPLICATION_URL | Repository variable | github_actions_variables.AZURE_APPLICATION_URL |
| AZURE_DEPLOY_ENABLED | Repository variable | true to enable deployment on pushes to main |

Transfer the sensitive deployment token directly into the secret through your secure tooling. For example, with GitHub CLI authenticated and the correct repository selected:

```powershell
terraform output -raw deployment_token | gh secret set AZURE_STATIC_WEB_APPS_API_TOKEN --env azure-production --repo OWNER/REPOSITORY
```

The token is sensitive and is stored in Terraform state. Do not commit it or include it in public configuration. Use a deployment token from this Static Web App, not a token for the former container app. If the token is rotated, update the GitHub secret.

Run **Deploy to Azure Static Web Apps** manually on main, or enable AZURE_DEPLOY_ENABLED and push to main. The workflow validates and tests Terraform with mocks, runs desktop/mobile browser tests, then uploads public/ using Azure/static-web-apps-deploy with the app build skipped and no API directory. It checks the live index and project list afterward.

No Azure login credentials or GHCR package access are required by the publishing workflow. Azure's managed service serves the frontend assets. Verify live API connectivity, CORS, and message delivery separately; browser tests mock those endpoints.

## Publish directly from your computer

After provisioning, you can publish the current local public/ files without committing or running GitHub Actions. From the repository root in PowerShell:

```powershell
$env:SWA_CLI_DEPLOYMENT_TOKEN = terraform -chdir=terraform/azure output -raw deployment_token
try {
  npx --yes --package @azure/static-web-apps-cli@2.1.0 swa deploy ./public --env production --no-use-keychain
} finally {
  Remove-Item Env:SWA_CLI_DEPLOYMENT_TOKEN -ErrorAction SilentlyContinue
}
```

The token is passed through the environment and cleared afterward. The deployment uploads only the frontend assets. Allow the site's exact HTTPS origin in the external API's CORS configuration, including GET, POST, OPTIONS, and the Content-Type header. This deployment configures that origin at the backend Container App ingress; preserve the same setting in the backend's own infrastructure configuration.

## Migrate the previous Container Apps deployment

Keep the existing Terraform state and resource group location. Remove obsolete container_image and github_oidc_subject inputs from local tfvars or CI variable sets. The current example lists all supported inputs.

The plan removes the container app, Consumption environment, user-assigned GitHub identity, federation credential, and role assignment, and creates a Static Web App. The resource group keeps its address and name. Review the plan before applying, especially the removal of the previous hosting resources.

This is a hosting replacement with a new azurestaticapps.net hostname. Applying removes the old endpoint; publish immediately afterward and update links, any custom domain configuration, and the external API's allowed CORS origins. Schedule the cutover because the new site has no frontend content until publication.

Remove obsolete AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID, AZURE_RESOURCE_GROUP, and AZURE_CONTAINER_APP GitHub variables once the new workflow is configured. GHCR images/packages are no longer used; remove them separately if they are not needed for another deployment. This Terraform change does not delete GitHub packages or settings.

## State, updates, and removal

Keep state and saved plans private and backed up because the state includes the deployment token. For provider upgrades, refresh Windows/Linux checksums and commit the lock file:

```powershell
terraform providers lock -platform=windows_amd64 -platform=linux_amd64
```

CI initializes with -lockfile=readonly. Terraform ignores repository_url and repository_branch changes populated by the deployment action; source publishing is owned by the workflow.

To remove hosting, disable automatic publishing, review terraform plan -destroy, and run terraform destroy from this directory. GitHub settings and the external API remain separate.
