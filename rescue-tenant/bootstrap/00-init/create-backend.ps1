param(
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,

    [string]$Location = "uksouth",
    [string]$Prefix = "rescue"
)

Write-Host "=== Rescue Tenant Bootstrap: Terraform Backend Creation ===" -ForegroundColor Cyan

# Names
$rgName = "$Prefix-backend-rg"
$saName = "$Prefix" + "tfstate" + (Get-Random -Maximum 9999)
$containerName = "tfstate"
$kvName = "$Prefix-backend-kv"

Write-Host "Using Subscription: $SubscriptionId"
az account set --subscription $SubscriptionId

Write-Host "Creating Resource Group: $rgName"
az group create -n $rgName -l $Location | Out-Null

Write-Host "Creating Storage Account: $saName"
az storage account create `
    -n $saName `
    -g $rgName `
    -l $Location `
    --sku Standard_LRS `
    --kind StorageV2 | Out-Null

Write-Host "Retrieving Storage Key"
$saKey = az storage account keys list -g $rgName -n $saName --query "[0].value" -o tsv

Write-Host "Creating Blob Container: $containerName"
az storage container create `
    -n $containerName `
    --account-name $saName `
    --account-key $saKey | Out-Null

Write-Host "Creating Key Vault: $kvName"
az keyvault create `
    -n $kvName `
    -g $rgName `
    -l $Location | Out-Null

Write-Host "Writing backend.tf"
$backendContent = @"
terraform {
  backend "azurerm" {
    resource_group_name  = "$rgName"
    storage_account_name = "$saName"
    container_name       = "$containerName"
    key                  = "terraform.tfstate"
  }
}
"@

$backendPath = Join-Path $PSScriptRoot "..\backend.tf"
$backendContent | Out-File -FilePath $backendPath -Encoding utf8

Write-Host "backend.tf written to $backendPath" -ForegroundColor Green

Write-Host "=== Backend Creation Complete ===" -ForegroundColor Cyan
Write-Host "Resource Group: $rgName"
Write-Host "Storage Account: $saName"
Write-Host "Container: $containerName"
Write-Host "Key Vault: $kvName"
