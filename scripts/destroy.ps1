# Tear down the dev environment so it stops costing money (~$2-3/day while running).
# Rebuild any time with .\scripts\deploy.ps1 or by re-running the Terraform workflow.
#
# The bootstrap stack (state bucket, GitHub OIDC role, budget) costs almost nothing and is kept.
# To remove it too:  cd terraform\bootstrap; terraform destroy
#   (empty the state bucket first, since it has versioning turned on)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

Push-Location "$Root\terraform\envs\dev"
terraform init -input=false
terraform destroy -input=false -auto-approve
if ($LASTEXITCODE -ne 0) { Pop-Location; throw "terraform destroy failed" }
Pop-Location

Write-Host "`nDev environment destroyed." -ForegroundColor Green
