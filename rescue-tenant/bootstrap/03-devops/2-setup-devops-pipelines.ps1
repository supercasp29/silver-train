param(
    [Parameter(Mandatory=$false)]
    [string]$OrgName = "supercasp29",

    [Parameter(Mandatory=$true)]
    [string]$ProjectName,                  # e.g. slinky-puppy

    [Parameter(Mandatory=$true)]
    [string]$RepoName,                     # usually same as project

    [Parameter(Mandatory=$true)]
    [string]$TerraformSP_AppId,            # clientId of rescue-terraform-sp

    [Parameter(Mandatory=$true)]
    [string]$TerraformSP_TenantId,         # tenantId of Bondi Rescue

    [Parameter(Mandatory=$true)]
    [string]$TerraformSP_Secret,           # secret for rescue-terraform-sp

    [Parameter(Mandatory=$true)]
    [string]$IdentitySP_AppId,             # clientId of rescue-identity-sp

    [Parameter(Mandatory=$true)]
    [string]$IdentitySP_TenantId,          # tenantId of Bondi Rescue

    [Parameter(Mandatory=$true)]
    [string]$IdentitySP_Secret,            # secret for rescue-identity-sp

    [Parameter(Mandatory=$true)]
    [string]$DevOpsPAT                     # PAT for supercasp29 org
)

Write-Host "=== Azure DevOps Bootstrap: Pipelines + Service Connections ===" -ForegroundColor Cyan

# --------------------------------------------------------------------
# 1. Ensure Azure DevOps authentication (safe pattern)
# --------------------------------------------------------------------
Write-Host "Ensuring Azure DevOps identity is correct..." -ForegroundColor Cyan

$devopsProfile = az devops configure -l 2>$null

if ($devopsProfile) {
    Write-Host "Azure DevOps already authenticated." -ForegroundColor Green
} else {
    Write-Host "Logging into Azure DevOps org: https://dev.azure.com/$OrgName" -ForegroundColor Cyan
    $DevOpsPAT | az devops login --organization "https://dev.azure.com/$OrgName"
    Write-Host "Azure DevOps authentication OK." -ForegroundColor Green
}

# --------------------------------------------------------------------
# 2. Create Terraform Service Connection (ARM)
# --------------------------------------------------------------------
Write-Host "Checking Terraform service connection..." -ForegroundColor Cyan

$tfSC = az devops service-endpoint list `
    --organization "https://dev.azure.com/$OrgName" `
    --project $ProjectName `
    --query "[?name=='terraform-sp']" -o tsv

if ($tfSC) {
    Write-Host "Terraform service connection already exists. Skipping." -ForegroundColor Yellow
} else {
    Write-Host "Creating Terraform service connection..." -ForegroundColor Cyan

    az devops service-endpoint azurerm create `
        --organization "https://dev.azure.com/$OrgName" `
        --project $ProjectName `
        --name "terraform-sp" `
        --azure-rm-service-principal-id $TerraformSP_AppId `
        --azure-rm-service-principal-key $TerraformSP_Secret `
        --azure-rm-tenant-id $TerraformSP_TenantId `
        --azure-rm-subscription-id "" `
        --azure-rm-subscription-name "" `
        --only-show-errors | Out-Null

    Write-Host "Terraform service connection created." -ForegroundColor Green
}

# --------------------------------------------------------------------
# 3. Create Identity Service Connection (ARM)
# --------------------------------------------------------------------
Write-Host "Checking Identity service connection..." -ForegroundColor Cyan

$idSC = az devops service-endpoint list `
    --organization "https://dev.azure.com/$OrgName" `
    --project $ProjectName `
    --query "[?name=='identity-sp']" -o tsv

if ($idSC) {
    Write-Host "Identity service connection already exists. Skipping." -ForegroundColor Yellow
} else {
    Write-Host "Creating Identity service connection..." -ForegroundColor Cyan

    az devops service-endpoint azurerm create `
        --organization "https://dev.azure.com/$OrgName" `
        --project $ProjectName `
        --name "identity-sp" `
        --azure-rm-service-principal-id $IdentitySP_AppId `
        --azure-rm-service-principal-key $IdentitySP_Secret `
        --azure-rm-tenant-id $IdentitySP_TenantId `
        --azure-rm-subscription-id "" `
        --azure-rm-subscription-name "" `
        --only-show-errors | Out-Null

    Write-Host "Identity service connection created." -ForegroundColor Green
}

# --------------------------------------------------------------------
# 4. Upload YAML pipeline definitions to the repo
# --------------------------------------------------------------------
Write-Host "Uploading pipeline YAML files..." -ForegroundColor Cyan

$repoUrl = "https://dev.azure.com/$OrgName/$ProjectName/_git/$RepoName"

git add .
git commit -m "Add pipeline YAML definitions" --allow-empty
git push origin main

Write-Host "Pipeline YAML committed to repo." -ForegroundColor Green

# --------------------------------------------------------------------
# 5. Create CI Pipeline
# --------------------------------------------------------------------
Write-Host "Checking CI pipeline..." -ForegroundColor Cyan

$ciPipe = az pipelines list `
    --organization "https://dev.azure.com/$OrgName" `
    --project $ProjectName `
    --query "[?name=='CI']" -o tsv

if ($ciPipe) {
    Write-Host "CI pipeline already exists. Skipping." -ForegroundColor Yellow
} else {
    Write-Host "Creating CI pipeline..." -ForegroundColor Cyan

    az pipelines create `
        --name "CI" `
        --organization "https://dev.azure.com/$OrgName" `
        --project $ProjectName `
        --repository $RepoName `
        --branch main `
        --yml-path "pipelines/ci.yml" `
        --only-show-errors | Out-Null

    Write-Host "CI pipeline created." -ForegroundColor Green
}

# --------------------------------------------------------------------
# 6. Create CD Pipeline
# --------------------------------------------------------------------
Write-Host "Checking CD pipeline..." -ForegroundColor Cyan

$cdPipe = az pipelines list `
    --organization "https://dev.azure.com/$OrgName" `
    --project $ProjectName `
    --query "[?name=='CD']" -o tsv

if ($cdPipe) {
    Write-Host "CD pipeline already exists. Skipping." -ForegroundColor Yellow
} else {
    Write-Host "Creating CD pipeline..." -ForegroundColor Cyan

    az pipelines create `
        --name "CD" `
        --organization "https://dev.azure.com/$OrgName" `
        --project $ProjectName `
        --repository $RepoName `
        --branch main `
        --yml-path "pipelines/cd.yml" `
        --only-show-errors | Out-Null

    Write-Host "CD pipeline created." -ForegroundColor Green
}

# --------------------------------------------------------------------
# 7. Summary
# --------------------------------------------------------------------
Write-Host "=== Azure DevOps Pipelines + Service Connections Ready ===" -ForegroundColor Green
Write-Host "Organization : $OrgName"
Write-Host "Project      : $ProjectName"
Write-Host "Repo         : $RepoName"
Write-Host "CI Pipeline  : CI"
Write-Host "CD Pipeline  : CD"
Write-Host "=========================================================" -ForegroundColor Cyan
