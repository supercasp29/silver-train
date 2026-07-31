param(
    [Parameter(Mandatory = $true)]
    [string]$OrgName,          # e.g. "supercasp29"
    [Parameter(Mandatory = $true)]
    [string]$ProjectName,      # e.g. "slinky-puppy"
    [Parameter(Mandatory = $true)]
    [string]$AzureDevOpsPAT    # PAT with pipeline + code rights
)

Write-Host "=== Setting up repo structure ==="

# Ensure folders exist
New-Item -ItemType Directory -Path "terraform" -Force | Out-Null
New-Item -ItemType Directory -Path "identity" -Force | Out-Null

# Drop a placeholder Terraform file
$tfMain = @'
terraform {
  required_version = ">= 1.5.0"
}

provider "azurerm" {
  features {}
}
'@
Set-Content -Path "terraform/main.tf" -Value $tfMain -Encoding UTF8

# Drop a placeholder identity script
$identityScript = @'
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,
    [Parameter(Mandatory = $true)]
    [string]$ClientId,
    [Parameter(Mandatory = $true)]
    [string]$ClientSecret
)

Write-Host "Creating users via Microsoft Graph..."
# TODO: Implement actual Graph calls here
'@
Set-Content -Path "identity/create-users.ps1" -Value $identityScript -Encoding UTF8

Write-Host "=== Writing pipeline YAML files ==="

# Terraform pipeline YAML
$terraformYaml = @'
trigger:
  branches:
    include:
      - master
  paths:
    include:
      - terraform/*

pool:
  vmImage: ubuntu-latest

steps:
- task: AzureCLI@2
  displayName: "Terraform Init & Plan"
  inputs:
    azureSubscription: "Terraform-SP"
    scriptType: bash
    scriptLocation: inlineScript
    inlineScript: |
      cd terraform
      terraform init
      terraform plan
'@
Set-Content -Path "azure-pipelines-terraform.yml" -Value $terraformYaml -Encoding UTF8

# Identity pipeline YAML
$identityYaml = @'
trigger:
  branches:
    include:
      - master
  paths:
    include:
      - identity/*

pool:
  vmImage: ubuntu-latest

steps:
- task: PowerShell@2
  displayName: "Create Users via Microsoft Graph"
  inputs:
    targetType: inline
    script: |
      cd identity
      pwsh ./create-users.ps1 -TenantId "$(tenantId)" -ClientId "$(clientId)" -ClientSecret "$(clientSecret)"
'@
Set-Content -Path "azure-pipelines-identity.yml" -Value $identityYaml -Encoding UTF8

Write-Host "=== Committing changes locally ==="

git add terraform identity azure-pipelines-terraform.yml azure-pipelines-identity.yml
git commit -m "Add Terraform and Identity pipelines"
git push

Write-Host "=== Creating pipelines in Azure DevOps ==="

$baseUrl = "https://dev.azure.com/$OrgName"
$auth = ("{0}:{1}" -f "", $AzureDevOpsPAT)
$authHeader = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($auth))

# Terraform pipeline
$tfPipelineBody = @{
    name        = "Terraform-Pipeline"
    folder      = "\\"
    configuration = @{
        type = "yaml"
        path = "azure-pipelines-terraform.yml"
    }
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri "$baseUrl/$ProjectName/_apis/pipelines?api-version=7.0" `
    -Method Post `
    -Headers @{ Authorization = $authHeader } `
    -ContentType "application/json" `
    -Body $tfPipelineBody | Out-Null

# Identity pipeline
$idPipelineBody = @{
    name        = "Identity-Pipeline"
    folder      = "\\"
    configuration = @{
        type = "yaml"
        path = "azure-pipelines-identity.yml"
    }
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri "$baseUrl/$ProjectName/_apis/pipelines?api-version=7.0" `
    -Method Post `
    -Headers @{ Authorization = $authHeader } `
    -ContentType "application/json" `
    -Body $idPipelineBody | Out-Null

Write-Host "=== Done: two pipelines wired to folder changes ==="
