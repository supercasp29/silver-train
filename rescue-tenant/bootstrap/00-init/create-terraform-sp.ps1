param(
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,

    [string]$Prefix = "rescue",
    [string]$Location = "uksouth"
)

Write-Host "=== Rescue Tenant Bootstrap: Terraform Service Principal Creation ===" -ForegroundColor Cyan

# Names
$rgName = "$Prefix-backend-rg"
$kvName = "$Prefix-backend-kv"
$spName = "$Prefix-terraform-sp"

Write-Host "Using Subscription: $SubscriptionId"
az account set --subscription $SubscriptionId

# Check Key Vault exists
$kvExists = az keyvault show -n $kvName -g $rgName --query "name" -o tsv 2>$null
if (-not $kvExists) {
    Write-Host "ERROR: Key Vault $kvName does not exist. Run create-backend.ps1 first." -ForegroundColor Red
    exit 1
}

# Check if SP already exists
$existingSp = az ad sp list --display-name $spName --query "[0].appId" -o tsv
if ($existingSp) {
    Write-Host "Service Principal already exists: $existingSp" -ForegroundColor Yellow
    $appId = $existingSp
} else {
    Write-Host "Creating Service Principal: $spName"
    $sp = az ad sp create-for-rbac `
        --name $spName `
        --role Contributor `
        --scopes "/subscriptions/$SubscriptionId" `
        --query "{appId:appId, tenant:tenant, password:password}" -o json

    $appId = ($sp | ConvertFrom-Json).appId
    $tenantId = ($sp | ConvertFrom-Json).tenant
    $secret = ($sp | ConvertFrom-Json).password

    Write-Host "Storing SP secret in Key Vault"
    az keyvault secret set `
        --vault-name $kvName `
        --name "$Prefix-terraform-sp-secret" `
        --value $secret | Out-Null
}

Write-Host "Retrieving stored secret"
$storedSecret = az keyvault secret show `
    --vault-name $kvName `
    --name "$Prefix-terraform-sp-secret" `
    --query "value" -o tsv

Write-Host "=== Terraform SP Details ===" -ForegroundColor Green
Write-Host "appId: $appId"
Write-Host "tenantId: $tenantId"
Write-Host "clientSecret: (stored in Key Vault)"
Write-Host "Key Vault Secret Name: $Prefix-terraform-sp-secret"
Write-Host "Key Vault: $kvName"

Write-Host "=== Bootstrap SP Creation Complete ===" -ForegroundColor Cyan
