# Load credentials into Terraform's input variable in this PowerShell session.
[CmdletBinding()]
param(
    [string]$Profile
)

$ErrorActionPreference = 'Stop'

# Do not leave stale Terraform credentials active if the export fails.
Remove-Item Env:TF_VAR_aws_credentials -ErrorAction SilentlyContinue

$awsArguments = @('configure', 'export-credentials', '--format', 'process')
if ($Profile) {
    $awsArguments += @('--profile', $Profile)
}

try {
    $credentialJson = & aws @awsArguments
    if ($LASTEXITCODE -ne 0) {
        throw 'AWS credential export failed. Authenticate your AWS CLI profile and try again.'
    }

    $credentials = ($credentialJson -join "`n") | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($credentials.AccessKeyId) -or
        [string]::IsNullOrWhiteSpace($credentials.SecretAccessKey)) {
        throw 'AWS credential export did not return an access key and secret key.'
    }

    $env:TF_VAR_aws_credentials = @{
        access_key_id     = $credentials.AccessKeyId
        secret_access_key = $credentials.SecretAccessKey
        session_token     = [string]$credentials.SessionToken
    } | ConvertTo-Json -Compress
}
finally {
    Remove-Variable credentials, credentialJson -ErrorAction SilentlyContinue
}

Write-Host 'AWS credentials loaded for Terraform in this PowerShell session. Temporary credentials must be refreshed and reapplied before they expire.'
