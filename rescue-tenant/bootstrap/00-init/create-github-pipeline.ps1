Write-Host "=== Creating GitHub Repo Structure ==="

# Create folders
$folders = @(
    ".github/workflows",
    "rescue-tenant/bootstrap/00-init",
    "rescue-tenant/bootstrap/01-terraform",
    "rescue-tenant/bootstrap/02-pipeline"
)

foreach ($f in $folders) {
    if (-not (Test-Path $f)) {
        New-Item -ItemType Directory -Path $f | Out-Null
        Write-Host "Created folder: $f"
    }
}

Write-Host "=== Writing GitHub Actions Workflow ==="

$workflow = @'
name: Rescue Tenant Bootstrap

on:
  workflow_dispatch:
  push:
    branches:
      - main

jobs:
  bootstrap:
    runs-on: ubuntu-latest

    permissions:
      id-token: write
      contents: read

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Azure Login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_TF_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TF_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Install Azure CLI Key Vault extension
        run: |
          az extension add --name keyvault --upgrade

      - name: Pull Terraform SP secret from Key Vault
        run: |
          SECRET=$(az keyvault secret show \
            --vault-name rescue-backend-kv \
            --name rescue-terraform-sp-secret \
            --query value -o tsv)

          echo "TF_VAR_client_secret=$SECRET" >> $GITHUB_ENV

      - name: Run Terraform backend bootstrap
        working-directory: rescue-tenant/bootstrap/01-terraform
        run: |
          pwsh ./init-terraform.ps1 -SubscriptionId "${{ secrets.AZURE_SUBSCRIPTION_ID }}"

      - name: Upload generated tfvars as artifact
        uses: actions/upload-artifact@v4
        with:
          name: terraform-tfvars
          path: rescue-tenant/bootstrap/01-terraform/terraform.tfvars
'@

Set-Content -Path ".github/workflows/azure-bootstrap.yml" -Value $workflow -Encoding UTF8
Write-Host "Workflow written."

Write-Host "=== Writing Terraform Init Script ==="

$tfInit = @'
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId
)

Write-Host "=== Rescue Tenant Bootstrap: Terraform Initialization ==="
Write-Host "Using Subscription: $SubscriptionId"

az account set --subscription $SubscriptionId

Write-Host "Retrieving Terraform SP secret from Key Vault..."
$clientSecret = az keyvault secret show --vault-name rescue-backend-kv --name rescue-terraform-sp-secret --query "value" -o tsv

Write-Host "Generating terraform.tfvars..."

@"
subscription_id = "$SubscriptionId"
tenant_id       = "0c46d62d-1c6e-4565-b44f-dbdbe0c8f08f"
client_id       = "6a382b35-2694-4b2b-9c63-9f74f8f14f32"
client_secret   = "$clientSecret"

backend_storage_account = "rescuetfstate"
backend_container       = "tfstate"
backend_key             = "rescue.terraform.tfstate"
"@ | Out-File -FilePath "./terraform.tfvars" -Encoding utf8

Write-Host "terraform.tfvars written."

Write-Host "Running terraform init..."
terraform init

Write-Host "=== Terraform Initialization Complete ==="
'@

Set-Content -Path "rescue-tenant/bootstrap/01-terraform/init-terraform.ps1" -Value $tfInit -Encoding UTF8
Write-Host "Terraform init script written."

Write-Host "=== GitHub Pipeline Bootstrap Complete ==="
