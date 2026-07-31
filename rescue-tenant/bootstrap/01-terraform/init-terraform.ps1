param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId
)

$appId = "6a382b35-2694-4b2b-9c63-9f74f8f14f32"
$tenantId = "0c46d62d-1c6e-4565-b44f-dbdbe0c8f08f"

Write-Host "=== Rescue Tenant Bootstrap: Terraform Initialization ==="

# Select subscription
Write-Host "Using Subscription: $SubscriptionId"
az account set --subscription $SubscriptionId

# Load Terraform SP details from Key Vault
$kvName = "rescue-backend-kv"
$secretName = "rescue-terraform-sp-secret"

Write-Host "Retrieving Terraform SP secret from Key Vault..."
$clientSecret = az keyvault secret show --vault-name $kvName --name $secretName --query "value" -o tsv

if (-not $clientSecret) {
    Write-Host "ERROR: Could not retrieve SP secret from Key Vault." -ForegroundColor Red
    exit 1
}

# Get SP appId and tenantId
$spName = "rescue-terraform-sp"
$appId = az ad sp list --display-name $spName --query "[0].appId" -o tsv
$tenantId = az ad sp list --display-name $spName --query "[0].tenant" -o tsv

if (-not $appId -or -not $tenantId) {
    Write-Host "ERROR: Could not retrieve SP details." -ForegroundColor Red
    exit 1
}

# Backend storage details
$rgName = "rescue-backend-rg"
$storageName = "rescuetfstate"
$containerName = "tfstate"
$stateKey = "rescue.terraform.tfstate"

Write-Host "Generating terraform.tfvars..."

@"
subscription_id = "$SubscriptionId"
tenant_id       = "$tenantId"
client_id       = "$appId"
client_secret   = "$clientSecret"

backend_storage_account = "$storageName"
backend_container       = "$containerName"
backend_key             = "$stateKey"
"@ | Out-File -FilePath "./terraform.tfvars" -Encoding utf8

Write-Host "terraform.tfvars written."

Write-Host "Running terraform init..."
terraform init

Write-Host "=== Terraform Initialization Complete ==="
