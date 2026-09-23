# Point the black-box probe at the current production URL.
# The sslip.io hostname is derived from the EC2 public IP, which changes when the
# AWS Academy session restarts, so the target is generated from Terraform output.
$url = (terraform -chdir="$PSScriptRoot\..\terraform" output -raw app_url)
if ($LASTEXITCODE -ne 0 -or -not $url) { throw "Could not read app_url from Terraform (are AWS credentials valid?)" }
$yml = "- targets: [`"$url/`"]`n  labels:`n    env: production`n"
New-Item -ItemType Directory -Force "$PSScriptRoot\prometheus\targets.d" | Out-Null
[System.IO.File]::WriteAllText("$PSScriptRoot\prometheus\targets.d\production.yml", $yml)
Write-Host "Production probe target: $url/"