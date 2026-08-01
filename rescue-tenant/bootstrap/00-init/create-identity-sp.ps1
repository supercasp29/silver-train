param(
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,

    [string]$Prefix = "rescue",
    [string]$Location = "uksouth"
)

Write-Host "=== Rescue Tenant Bootstrap: Identity Service Principal Creation ===" -ForegroundColor Cyan

# Names
$rgName = "$Prefix-backend-rg"
$kvName = "$Prefix-backend-kv"
$spName = "$Prefix-identity-sp"
$secretName = "$Prefix-identity-sp-secret"

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
    Write-Host "Identity SP already exists: $existingSp" -ForegroundColor Yellow
    $appId = $existingSp
} else {
    Write-Host "Creating Identity Service Principal: $spName"

    # Create App Registration + SP
    $sp = az ad sp create-for-rbac `
        --name $spName `
        --skip-assignment `
        --query "{appId:appId, tenant:tenant, password:password}" -o json

    $appId = ($sp | ConvertFrom-Json).appId
    $tenantId = ($sp | ConvertFrom-Json).tenant
    $secret = ($sp | ConvertFrom-Json).password

    Write-Host "Storing Identity SP secret in Key Vault"
    az keyvault secret set `
        --vault-name $kvName `
        --name $secretName `
        --value $secret | Out-Null
}

# Retrieve stored secret
$storedSecret = az keyvault secret show `
    --vault-name $kvName `
    --name $secretName `
    --query "value" -o tsv

Write-Host "Assigning Microsoft Graph API permissions..." -ForegroundColor Cyan

# Add Graph API permissions
az ad app permission add `
    --id $appId `
    --api 00000003-0000-0000-c000-000000000000 `
    --api-permissions "User.ReadWrite.All=Role" "Directory.ReadWrite.All=Role" "Organization.Read.All=Role"

# Grant admin consent
az ad app permission admin-consent --id $appId

Write-Host "Assigning Entra Directory Role: User Administrator..." -ForegroundColor Cyan

# Get SP objectId
$objectId = az ad sp show --id $appId --query "id" -o tsv

# User Administrator role template ID
$roleTemplateId = "fe930be7-5e62-47db-91af-98c3a49a38b1"

# Activate role if needed
$roleId = az rest --method GET `
    --uri "https://graph.microsoft.com/v1.0/directoryRoles" `
    --query "value[?roleTemplateId=='$roleTemplateId'].id" -o tsv

if (-not $roleId) {
    Write-Host "Activating User Administrator role..."
    $roleId = az rest --method POST `
        --uri "https://graph.microsoft.com/v1.0/directoryRoles" `
        --body "{ \"roleTemplateId\": \"$roleTemplateId\" }" `
        --query "id" -o tsv
}

# Assign SP to role
az rest `
    --method POST `
    --uri "https://graph.microsoft.com/v1.0/directoryRoles/$roleId/members/\$ref" `
    --body "{ \"@odata.id\": \"https://graph.microsoft.com/v1.0/directoryObjects/$objectId\" }"

Write-Host "=== Identity SP Details ===" -ForegroundColor Green
Write-Host "appId: $appId"
Write-Host "tenantId: $tenantId"
Write-Host "clientSecret: (stored in Key Vault)"
Write-Host "Key Vault Secret Name: $secretName"
Write-Host "Key Vault: $kvName"

Write-Host "=== Identity SP Creation Complete ===" -ForegroundColor Cyan
