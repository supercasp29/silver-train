param(
    [Parameter(Mandatory=$false)]
    [string]$OrgName = "supercasp29",

    [Parameter(Mandatory=$true)]
    [string]$ProjectName,          # e.g. slinky-puppy

    [string]$RepoName = $ProjectName,

    [Parameter(Mandatory=$true)]
    [string]$DevOpsPAT             # PAT for supercasp29 org
)

Write-Host "=== Azure DevOps Bootstrap: Project + Repo Creation (Idempotent) ===" -ForegroundColor Cyan

# --------------------------------------------------------------------
# 1. Ensure Azure DevOps authentication (no logout, no hang)
# --------------------------------------------------------------------
Write-Host "Ensuring Azure DevOps identity is correct..." -ForegroundColor Cyan

$devopsProfile = az devops configure -l 2>$null

if ($devopsProfile) {
    Write-Host "Azure DevOps already authenticated." -ForegroundColor Green
} else {
    Write-Host "Logging into Azure DevOps org: https://dev.azure.com/$OrgName" -ForegroundColor Cyan

    # PAT must be piped into the login command
    $DevOpsPAT | az devops login --organization "https://dev.azure.com/$OrgName"

    Write-Host "Azure DevOps authentication OK." -ForegroundColor Green
}

# --------------------------------------------------------------------
# 2. Check if project exists
# --------------------------------------------------------------------
Write-Host "Checking if project '$ProjectName' exists..." -ForegroundColor Cyan

$project = az devops project show `
    --organization "https://dev.azure.com/$OrgName" `
    --project $ProjectName `
    --query "name" -o tsv 2>$null

if ($project) {
    Write-Host "Project '$ProjectName' already exists. Skipping creation." -ForegroundColor Yellow
} else {
    Write-Host "Project '$ProjectName' does not exist. Creating..." -ForegroundColor Cyan

    az devops project create `
        --name $ProjectName `
        --organization "https://dev.azure.com/$OrgName" `
        --visibility private `
        --source-control git `
        --only-show-errors | Out-Null

    Write-Host "Project '$ProjectName' created." -ForegroundColor Green
}

# --------------------------------------------------------------------
# 3. Check if repo exists
# --------------------------------------------------------------------
Write-Host "Checking if repo '$RepoName' exists..." -ForegroundColor Cyan

$repo = az repos show `
    --organization "https://dev.azure.com/$OrgName" `
    --project $ProjectName `
    --repository $RepoName `
    --query "name" -o tsv 2>$null

if ($repo) {
    Write-Host "Repo '$RepoName' already exists. Skipping creation." -ForegroundColor Yellow
} else {
    Write-Host "Repo '$RepoName' does not exist. Creating..." -ForegroundColor Cyan

    az repos create `
        --name $RepoName `
        --project $ProjectName `
        --organization "https://dev.azure.com/$OrgName" `
        --only-show-errors | Out-Null

    Write-Host "Repo '$RepoName' created." -ForegroundColor Green
}

# --------------------------------------------------------------------
# 4. Output summary
# --------------------------------------------------------------------
Write-Host "=== Azure DevOps Project + Repo Ready (Idempotent) ===" -ForegroundColor Green
Write-Host "Organization : $OrgName"
Write-Host "Project      : $ProjectName"
Write-Host "Repository   : $RepoName"
Write-Host "URL          : https://dev.azure.com/$OrgName/$ProjectName/_git/$RepoName"
Write-Host "======================================================" -ForegroundColor Cyan
