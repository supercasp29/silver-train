param(
    [Parameter(Mandatory=$false)]
    [string]$OrgName = "supercasp29",

    [Parameter(Mandatory=$true)]
    [string]$ProjectName,

    [Parameter(Mandatory=$true)]
    [string]$RepoName,

    [Parameter(Mandatory=$true)]
    [string]$TerraformSP_AppId,

    [Parameter(Mandatory=$true)]
    [string]$TerraformSP_TenantId,

    [Parameter(Mandatory=$true)]
    [string]$TerraformSP_Secret,

    [Parameter(Mandatory=$true)]
    [string]$IdentitySP_AppId,

    [Parameter(Mandatory=$true)]
    [string]$IdentitySP_TenantId,

    [Parameter(Mandatory=$true)]
    [string]$IdentitySP_Secret,

    [Parameter(Mandatory=$true)]
    [string]$DevOpsPAT
)

Write-Host "=== Azure DevOps Bootstrap: Pipelines + Service Connections ===" -ForegroundColor Cyan

# --------------------------------------------------------------------
# 1. Ensure Azure DevOps authentication
# --------------------------------------------------------------------
$devopsProfile = az devops configure -l 2>$null

if (-not $devopsProfile) {
    Write-Host "Logging into Azure DevOps..." -ForegroundColor Cyan
    $DevOpsPAT | az devops login --organization "https://dev.azure.com/$OrgName"
}

# --------------------------------------------------------------------
# 2. Create Terraform Service Connection
# --------------------------------------------------------------------
Write-Host "Checking Terraform service connection..." -ForegroundColor Cyan

$tfSC = az devops service-endpoint list `
    --organization "https://dev.azure.com/$OrgName" `
    --project $ProjectName `
    --query "[?name=='terraform-sp']" -o tsv

if (-not $tfSC) {
    Write-Host "Creating Terraform service connection..." -ForegroundColor Cyan

    az devops service-endpoint azurerm create `
        --organization "https://dev.azure.com/$OrgName" `
        --project $ProjectName `
        --name "terraform-sp" `
        --azure-rm-service-principal-id $TerraformSP_AppId `
        --azure-rm-service-principal-key $TerraformSP_Secret `
        --azure-rm-tenant-id $TerraformSP_TenantId `
        --azure-rm-subscription-id "811295a3-72de-4c4d-913e-588fbdc61948" `
        --azure-rm-subscription-name "Bondi Rescue Subscription" `
        --only-show-errors | Out-Null

    Write-Host "Terraform service connection created." -ForegroundColor Green
} else {
    Write-Host "Terraform service connection already exists." -ForegroundColor Yellow
}

# --------------------------------------------------------------------
# 3. Create Identity Service Connection
# --------------------------------------------------------------------
Write-Host "Checking Identity service connection..." -ForegroundColor Cyan

$idSC = az devops service-endpoint list `
    --organization "https://dev.azure.com/$OrgName" `
    --project $ProjectName `
    --query "[?name=='identity-sp']" -o tsv

if (-not $idSC) {
    Write-Host "Creating Identity service connection..." -ForegroundColor Cyan

    az devops service-endpoint azurerm create `
        --organization "https://dev.azure.com/$OrgName" `
        --project $ProjectName `
        --name "identity-sp" `
        --azure-rm-service-principal-id $IdentitySP_AppId `
        --azure-rm-service-principal-key $IdentitySP_Secret `
        --azure-rm-tenant-id $IdentitySP_TenantId `
        --azure-rm-subscription-id "811295a3-72de-4c4d-913e-588fbdc61948" `
        --azure-rm-subscription-name "Bondi Rescue Subscription" `
        --only-show-errors | Out-Null

    Write-Host "Identity service connection created." -ForegroundColor Green
} else {
    Write-Host "Identity service connection already exists." -ForegroundColor Yellow
}

# --------------------------------------------------------------------
# 4. Commit YAML to Azure DevOps repo
# --------------------------------------------------------------------
Write-Host "Pushing pipeline YAML to Azure DevOps repo..." -ForegroundColor Cyan

git add .
git commit -m "Add pipeline YAML definitions" --allow-empty
git push origin main

Write-Host "Pipeline YAML committed." -ForegroundColor Green

# --------------------------------------------------------------------
# 5. Create CI Pipeline
# --------------------------------------------------------------------
Write-Host "Checking CI pipeline..." -ForegroundColor Cyan

$ciPipe = az pipelines list `
    --organization "https://dev.azure.com/$OrgName" `
    --project $ProjectName `
    --query "[?name=='CI']" -o tsv

if (-not $ciPipe) {
    Write-Host "Creating CI pipeline..." -ForegroundColor Cyan

    az pipelines create `
        --name "CI" `
        --organization "https://dev.azure.com/$OrgName" `
        --project $ProjectName `
        --repository $RepoName `
        --repository-type tfsgit `
        --branch main `
        --yml-path "pipelines/ci.yml" `
        --only-show-errors | Out-Null

    Write-Host "CI pipeline created." -ForegroundColor Green
} else {
    Write-Host "CI pipeline already exists." -ForegroundColor Yellow
}

# --------------------------------------------------------------------
# 6. Create CD Pipeline
# --------------------------------------------------------------------
Write-Host "Checking CD pipeline..." -ForegroundColor Cyan

$cdPipe = az pipelines list `
    --organization "https://dev.azure.com/$OrgName" `
    --project $ProjectName `
    --query "[?name=='CD']" -o tsv

if (-not $cdPipe) {
    Write-Host "Creating CD pipeline..." -ForegroundColor Cyan

    az pipelines create `
        --name "CD" `
        --organization "https://dev.azure.com/$OrgName" `
        --project $ProjectName `
        --repository $RepoName `
        --repository-type tfsgit `
        --branch main `
        --yml-path "pipelines/cd.yml" `
        --only-show-errors | Out-Null

    Write-Host "CD pipeline created." -ForegroundColor Green
} else {
    Write-Host "CD pipeline already exists." -ForegroundColor Yellow
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
Write-Host "========================================================="
