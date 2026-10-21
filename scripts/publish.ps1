# Push this project to a new, EMPTY GitHub repository.
# Usage:  .\scripts\publish.ps1 -RepoUrl https://github.com/<you>/cloud-portfolio-app.git

param(
    [Parameter(Mandatory = $true)][string]$RepoUrl
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

# Move the pipeline files into place (they were copied to _workflows first).
if (Test-Path "$Root\_workflows") {
    New-Item -ItemType Directory -Force -Path "$Root\.github\workflows" | Out-Null
    Move-Item -Force "$Root\_workflows\*.yml" "$Root\.github\workflows\"
    Remove-Item -Force "$Root\_workflows"
}

if (-not (Test-Path "$Root\.git")) { git init -b main }

if (-not (git config user.name))  { throw "Set your Git name first:  git config --global user.name ""Your Name""" }
if (-not (git config user.email)) { throw "Set your Git email first: git config --global user.email ""you@example.com""" }

git add -A
git commit -m "Production-style 3-tier app on AWS: Terraform, ECS Fargate, RDS, GitHub Actions with OIDC"
if ($LASTEXITCODE -ne 0) { Write-Host "Nothing new to commit." }

$existing = git remote
if ($existing -notcontains "origin") { git remote add origin $RepoUrl }
git push -u origin main
if ($LASTEXITCODE -ne 0) { throw "git push failed" }

Write-Host "`nPushed to $RepoUrl" -ForegroundColor Green
