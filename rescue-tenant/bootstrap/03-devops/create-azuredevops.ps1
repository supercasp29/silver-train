param(
    [Parameter(Mandatory = $true)]
    [string]$OrgName,
    [Parameter(Mandatory = $true)]
    [string]$ProjectName,
    [Parameter(Mandatory = $true)]
    [string]$AzureDevOpsPAT
)

Write-Host "=== Azure DevOps Bootstrap ==="

# Base URL
$baseUrl = "https://dev.azure.com/$OrgName"

# Auth header
$auth = ("{0}:{1}" -f "", $AzureDevOpsPAT)
$authHeader = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($auth))

# Create repo
Write-Host "Creating repo: rescue-tenant"
$repoBody = @{
    name = "rescue-tenant"
} | ConvertTo-Json

$repo = Invoke-RestMethod -Uri "$baseUrl/$ProjectName/_apis/git/repositories?api-version=7.0" `
    -Method Post `
    -Headers @{ Authorization = $authHeader } `
    -ContentType "application/json" `
    -Body $repoBody

$repoUrl = $repo.remoteUrl
Write-Host "Repo created: $repoUrl"

# Push local code into Azure DevOps repo
Write-Host "Pushing local code to Azure DevOps repo..."
git init
git remote add origin $repoUrl
git add .
git commit -m "Initial rescue-tenant bootstrap"
git push --set-upstream origin master

Write-Host "Code pushed."

# Create Terraform pipeline YAML
Write-Host "Creating Terraform pipeline YAML..."

$pipelineYaml = @'
trigger:
- master

pool:
  vmImage: ubuntu-latest

steps:
- task: AzureCLI@2
  displayName: "Login to Azure"
  inputs:
    azureSubscription: "Terraform-SP"
    scriptType: bash
    scriptLocation: inlineScript
    inlineScript: |
      echo "Logged into Azure."

- task: AzureKeyVault@2
  displayName: "Fetch Terraform SP Secret"
  inputs:
    azureSubscription: "Terraform-SP"
    KeyVaultName: "rescue-backend-kv"
    SecretsFilter: "rescue-terraform-sp-secret"

- script: |
    echo "Generating terraform.tfvars..."
    cat <<EOF > terraform.tfvars
subscription_id = "$(AZURE_SUBSCRIPTION_ID)"
tenant_id       = "0c46d62d-1c6e-4565-b44f-dbdbe0c8f08f"
client_id       = "6a382b35-2694-4b2b-9c63-9f74f8f14f32"
client_secret   = "$(rescue-terraform-sp-secret)"
backend_storage_account = "rescuetfstate"
backend_container       = "tfstate"
backend_key             = "rescue.terraform.tfstate"
EOF
  displayName: "Write tfvars"

- script: |
    terraform init
    terraform plan
  displayName: "Terraform Init & Plan"
'@

Set-Content -Path "azure-pipelines.yml" -Value $pipelineYaml -Encoding UTF8

Write-Host "Pipeline YAML written."

Write-Host "=== Azure DevOps Bootstrap Complete ==="
