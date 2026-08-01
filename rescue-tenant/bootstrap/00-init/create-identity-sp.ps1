param(
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,

    [string]$Prefix = "rescue"
)

Write-Host "=== Rescue Tenant Bootstrap: Identity Service Principal Creation ===" -ForegroundColor Cyan

# Names
$rgName = "$Prefix-backend-rg"
$kvName = "$Prefix-backend-kv"
$spName = "$Prefix-identity-sp"
$secretName = "$Prefix-identity-sp-secret"

az account set --subscription $SubscriptionId

# Check Key Vault exists
$kvExists = az keyvault show -n $kvName -g $rgName --query "name" -o tsv 2>$null
if (-not $kvExists) {
    Write-Host "ERROR: Key Vault $kvName does not exist." -ForegroundColor Red
    exit 1
}

# Check if SP exists
$existingSp = az ad sp list --display-name $spName --query "[0].appId" -o tsv
if ($existingSp) {
    Write-Host "Identity SP already exists: $existingSp"
    $appId = $existingSp
    $tenantId = az account show --query tenantId -o tsv
} else {
    Write-Host "Creating Identity SP: $spName"

    $sp = az ad sp create-for-rbac `
        --name $spName `
        --skip-assignment `
        --query "{appId:appId, tenant:tenant, password:password}" -o json

    $spObj = $sp | ConvertFrom-Json
    $appId = $spObj.appId
    $tenantId = $spObj.tenant
    $secret = $spObj.password

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

# Modern Graph permission GUIDs
$perm_UserReadWriteAll      = "741f803b-c850-494e-b5df-cde7c675a1ba"
$perm_DirectoryReadWriteAll = "19dbc75e-c2e2-444c-a770-ec69d8559fc7"
$perm_OrgReadAll            = "06da0dbc-49e2-44d2-8312-53f166ab848a"

# Add permissions
az ad app permission add `
  --id $appId `
  --api 00000003-0000-0000-c000-000000000000 `
  --api-permissions "$perm_UserReadWriteAll=Role" "$perm_DirectoryReadWriteAll=Role" "$perm_OrgReadAll=Role"

# Grant admin consent
az ad app permission admin-consent --id $appId

Write-Host "Assigning Entra Directory Role: User Administrator..." -ForegroundColor Cyan

# Get SP objectId
$objectId = az ad sp show --id $appId --query "id" -o tsv

# User Administrator role template ID
$roleTemplateId = "fe930be7-5e62-47db-91af-98c3a49a38b1"

# Check if role is activated
$roleId = az rest --method GET `
    --uri "https://graph.microsoft.com/v1.0/directoryRoles" `
    --query "value[?roleTemplateId=='$roleTemplateId'].id" -o tsv

if (-not $roleId) {
    Write-Host "Activating User Administrator role..."

    $activateBody = @{
        roleTemplateId = $roleTemplateId
    } | ConvertTo-Json

    $roleId = az rest `
        --method POST `
        --uri "https://graph.microsoft.com/v1.0/directoryRoles" `
        --headers "Content-Type=application/json" `
        --body $activateBody `
        --query "id" -o tsv
}

# Assign SP to role
$assignBody = @{
    "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$objectId"
} | ConvertTo-Json

az rest `
    --method POST `
    --uri "https://graph.microsoft.com/v1.0/directoryRoles/$roleId/members/\$ref" `
    --headers "Content-Type=application/json" `
    --body $assignBody

Write-Host "=== Identity SP Details ===" -ForegroundColor Green
Write-Host "appId: $appId"
Write-Host "tenantId: $tenantId"
Write-Host "clientSecret: (stored in Key Vault)"
Write-Host "Key Vault Secret Name: $secretName"
Write-Host "Key Vault: $kvName"
Write-Host "=== Identity SP Creation Complete ===" -ForegroundColor Cyan
