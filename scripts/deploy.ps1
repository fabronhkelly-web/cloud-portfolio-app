# First-time deployment from your own PC (Windows PowerShell).
# After this, GitHub Actions handles every deployment.
#
# Usage (from the project folder):
#   aws sso login
#   $env:TF_VAR_alert_email = "you@example.com"
#   .\scripts\deploy.ps1

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Region = "us-east-1"

function Invoke-Step($Title, [scriptblock]$Command) {
    Write-Host "`n=== $Title ===" -ForegroundColor Cyan
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "Step failed: $Title" }
}

# 1. Bootstrap: state bucket, GitHub OIDC role, budget (local state)
Push-Location "$Root\terraform\bootstrap"
Invoke-Step "Bootstrap: terraform init"  { terraform init -input=false }
Invoke-Step "Bootstrap: terraform apply" { terraform apply -input=false -auto-approve }
$RoleArn = terraform output -raw github_actions_role_arn
Pop-Location

# 2. Dev environment: create the image registry first, so there is an image to run
Push-Location "$Root\terraform\envs\dev"
Invoke-Step "Dev: terraform init" { terraform init -input=false }
Invoke-Step "Dev: create ECR repository" { terraform apply -input=false -auto-approve -target="module.ecr" }
$Repo = terraform output -raw ecr_repository_url
$Registry = $Repo.Split("/")[0]
Pop-Location

# 3. Build and push the first image.
# If Docker can't log in here, keep going: the GitHub Actions pipeline builds and pushes the image
# on the first push, and ECS starts the app as soon as the image exists.
Write-Host "`n=== Docker: log in, build, push ===" -ForegroundColor Cyan
$ImagePushed = $false
try {
    $Password = (aws ecr get-login-password --region $Region | Out-String).Trim()
    docker login --username AWS --password $Password $Registry 2>&1 | Write-Host
    if ($LASTEXITCODE -ne 0) { throw "docker login failed" }
    docker build -t "${Repo}:latest" "$Root\app"
    if ($LASTEXITCODE -ne 0) { throw "docker build failed" }
    docker push "${Repo}:latest"
    if ($LASTEXITCODE -ne 0) { throw "docker push failed" }
    $ImagePushed = $true
} catch {
    Write-Host "Skipping local image push ($($_.Exception.Message)). GitHub Actions will push it." -ForegroundColor Yellow
}

# 4. Everything else: VPC, database, ECS, load balancer, alarms (~10-15 minutes, mostly RDS)
Push-Location "$Root\terraform\envs\dev"
Invoke-Step "Dev: terraform apply (full)" { terraform apply -input=false -auto-approve }
$Url = terraform output -raw app_url
Pop-Location

Write-Host "`nDone." -ForegroundColor Green
Write-Host "App URL:       $Url"
Write-Host "AWS_ROLE_ARN:  $RoleArn   (add this as a GitHub repository variable)"
if ($ImagePushed) { Write-Host "The app can take 1-2 minutes to pass health checks after the first deploy." }
else { Write-Host "No image yet: the app starts after the first GitHub Actions deploy." -ForegroundColor Yellow }
