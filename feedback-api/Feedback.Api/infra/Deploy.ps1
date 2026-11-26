param(
    [Parameter(Mandatory)]
    [ValidatePattern('^ghcr\.io/[a-z0-9._/-]+(:[a-zA-Z0-9._-]+|@sha256:[a-f0-9]{64})$')]
    [string] $Image
)

$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    # Persist the selected version so later plans do not revert the deployed image.
    @{ container_image = $Image } | ConvertTo-Json |
        Set-Content -LiteralPath 'deployment.auto.tfvars.json' -Encoding utf8
    & terraform init -input=false
    if ($LASTEXITCODE -ne 0) { throw 'Terraform init failed.' }
    & terraform validate -no-color
    if ($LASTEXITCODE -ne 0) { throw 'Terraform validation failed.' }
    & terraform plan -input=false '-out=container-apps.tfplan'
    if ($LASTEXITCODE -ne 0) { throw 'Terraform plan failed.' }
    & terraform apply -input=false container-apps.tfplan
    if ($LASTEXITCODE -ne 0) { throw 'Terraform apply failed.' }
    & terraform output -raw container_app_url
} finally {
    Pop-Location
}

