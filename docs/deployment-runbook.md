# Deployment runbook

Last updated: 2026-09-23

How to operate CloudPulse on AWS, from an empty AWS Academy account to a running, monitored deployment.
All commands are for **Windows PowerShell 5.1** (the environment this project was built on), run from the repository root unless stated otherwise.

Each step is marked:
- **[verified]**: executed and observed working during the build
- **[not yet verified]**: written from the design, still to be tested end to end

---

## 0. Prerequisites

| Tool | Version used | Install |
|---|---|---|
| Git | any recent | `winget install -e --id Git.Git` |
| Docker Desktop | any recent | `winget install -e --id Docker.DockerDesktop` |
| Terraform | 1.16.2 (**>= 1.10 required** for S3-native locking) | `winget install -e --id Hashicorp.Terraform` |
| AWS CLI | v2 | `winget install -e --id Amazon.AWSCLI` |
| GitHub CLI | any recent | `winget install -e --id GitHub.cli`, then `gh auth login` |

AWS access: an **AWS Academy Learner Lab** (region `us-east-1`). The lab provides the `LabInstanceProfile` and the `vockey` key pair used by Terraform.

---

## 1. At the start of every lab session [verified]

Academy credentials expire when the lab session ends (about 4 hours), and the EC2 instance is stopped between sessions.

1. In Vocareum: **Start Lab**, wait for the green dot, open **AWS Details -> AWS CLI: Show**.
2. Write the credentials **without a BOM** (Windows PowerShell 5's `Set-Content -Encoding UTF8` adds a BOM that the AWS SDK cannot parse):

```powershell
   $content = @"
   [default]
   aws_access_key_id=PASTE
   aws_secret_access_key=PASTE
   aws_session_token=PASTE
   "@
   [System.IO.File]::WriteAllText("$HOME\.aws\credentials", $content)
```

3. One-time only, the region:

```powershell
   [System.IO.File]::WriteAllText("$HOME\.aws\config", "[default]`nregion = us-east-1`noutput = json`n")
```

4. Verify, then push the new credentials to GitHub Actions:

```powershell
   aws sts get-caller-identity
   powershell -ExecutionPolicy Bypass -File scripts\refresh-github-aws-secrets.ps1
```

5. If the AWS Console shows `explicit deny ... voc-cancel-cred`, the console tab is from an older session: close all console tabs and reopen the console from Vocareum.

### After a lab restart: redeploy [not yet verified]

When the instance starts again it gets a **new public IP**, so the sslip.io hostname changes. The containers restart automatically, but Caddy's certificate and Django's `ALLOWED_HOSTS` still refer to the old hostname. Redeploy so `deploy.sh` regenerates both:

```powershell
terraform -chdir=terraform apply -refresh-only -auto-approve   # refresh outputs (new IP) in state
terraform -chdir=terraform output app_url
gh workflow run cd.yml --repo rayenmabrouk/cloudpulse            # rebuild + redeploy through CD
```

If your home IP changed, update `terraform/terraform.tfvars` and the `TF_VAR_ALLOWED_SSH_CIDR` secret, then change the SSH rule through a pull request.

---

## 2. First-time setup from zero

### 2.1 Remote state bucket [verified]

The state bucket is created outside Terraform (Terraform cannot store its state in a bucket it has not created yet). The script is idempotent:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\bootstrap-tfstate.ps1
```

It creates `cloudpulse-tfstate-<account-id>` with versioning, SSE-S3 encryption, all public access blocked and a TLS-only bucket policy.

### 2.2 Infrastructure [verified]

```powershell
Copy-Item terraform\terraform.tfvars.example terraform\terraform.tfvars
# edit terraform.tfvars: allowed_ssh_cidr = "<your public IP>/32"
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
terraform output
cd ..
```

This creates the VPC, subnet, internet gateway, security groups, EC2 instance (Docker installed by `user_data`), ECR repository, SSM `SecureString` parameter with a generated Django `SECRET_KEY`, CloudWatch log group and alarms.

After this first bootstrap, **infrastructure changes go through pull requests** and the Terraform pipeline (section 4.2).

### 2.3 GitHub configuration [verified]

```powershell
# AWS credentials for CI/CD (repeat every lab session)
powershell -ExecutionPolicy Bypass -File scripts\refresh-github-aws-secrets.ps1

# SSH CIDR for the Terraform pipeline
gh secret set TF_VAR_ALLOWED_SSH_CIDR --repo rayenmabrouk/cloudpulse --body "<your public IP>/32"
```

Environments (created with `gh api`, see the PR history for exact commands):
- `production`: deployments allowed from `master` only (used by CD)
- `infrastructure`: `master` only **and a required reviewer** (used by Terraform apply)

Branch protection on `master`: pull request required, required checks `test`, `lint`, `docker-build-scan`, branch up to date, enforced for admins, no force-push or deletion.

### 2.4 First deployment [verified]

The first release was deployed manually to validate `deploy.sh`, then all later releases went through CD. To deploy the current `master` through CD:

```powershell
gh workflow run cd.yml --repo rayenmabrouk/cloudpulse
```

**[not yet verified]** The manual trigger (`workflow_dispatch`) runs the same jobs as a push but has not been exercised yet; every verified CD run was triggered by a merge.

Get the URL:

```powershell
terraform -chdir=terraform output app_url
```

---

## 3. What a deployment does (`scripts/deploy.sh`) [verified]

Runs on the instance as root (sent by SSM Run Command from CD):

1. Reads account ID and public IP from **IMDSv2** (session token required).
2. Authenticates to ECR with the **ECR credential helper** via the instance role (falls back to `docker login` if the helper is unavailable).
3. Pulls `cloudpulse:<tag>`.
4. Reads `SECRET_KEY` from SSM Parameter Store and writes a root-only env file (`umask 077`) with `DEBUG=False` and `ALLOWED_HOSTS=<host>,localhost,127.0.0.1`.
5. Replaces the `dpaste` container on a private Docker network, published on `127.0.0.1:8000` only, SQLite on the `dpaste_data` volume, logs to CloudWatch.
6. Health-checks `http://localhost:8000/` for up to 60 s. **On failure it restarts the previous image.**
7. Starts or reloads **Caddy** (ports 80/443, automatic Let's Encrypt certificate, JSON access logs to CloudWatch).
8. Installs the daily `cloudpulse-cleanup.timer`.

---

## 4. Day-to-day changes

### 4.1 Application, image or deploy script [verified]

```powershell
git checkout -b feature/my-change
# edit, commit
git push -u origin feature/my-change
gh pr create --repo rayenmabrouk/cloudpulse --base master --fill
gh pr checks <number> --repo rayenmabrouk/cloudpulse --watch
gh pr merge <number> --repo rayenmabrouk/cloudpulse --merge --delete-branch
```

The merge triggers CD when it touches `dpaste/`, `client/`, `Dockerfile.hardened`, `setup.*`, `package*.json`, `scripts/deploy.sh` or `.github/workflows/cd.yml`. Watch it:

```powershell
$RUN = gh run list --repo rayenmabrouk/cloudpulse --workflow cd.yml --limit 1 --json databaseId --jq ".[0].databaseId"
gh run watch $RUN --repo rayenmabrouk/cloudpulse --exit-status
```

### 4.2 Infrastructure [verified]

Same PR flow for changes under `terraform/`. On the PR, the Terraform workflow runs `fmt`, `validate`, Checkov and `plan` (the plan is in the run summary). After merge:

1. Actions -> the Terraform run -> the **Apply (manual approval)** job waits.
2. Review the plan in the run summary.
3. **Review deployments -> infrastructure -> Approve and deploy.**
4. Verify locally: `terraform -chdir=terraform plan` should report **No changes**.

A Checkov finding must be either fixed or skipped inline with a justification (`# checkov:skip=<ID>:<reason>`).

---

## 5. Operations

### Run a command on the server without SSH [verified]

```powershell
$ID = aws ec2 describe-instances --filters "Name=tag:Name,Values=cloudpulse-server" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text
[System.IO.File]::WriteAllText("$env:TEMP\cmd.json", '{"commands":["docker ps --format ''{{.Names}} {{.Image}} {{.Status}}''"]}')
$CMD = aws ssm send-command --instance-ids $ID --document-name AWS-RunShellScript --parameters "file://$env:TEMP\cmd.json" --query Command.CommandId --output text
Start-Sleep -Seconds 5
aws ssm get-command-invocation --command-id $CMD --instance-id $ID --query StandardOutputContent --output text
```

The AWS CLI on Windows crashes when the output contains emoji (dpaste's startup banner). Append `| tr -cd '\11\12\40-\176'` to the remote command to strip them.

### Logs [verified]

```powershell
aws logs tail /cloudpulse/dpaste --since 15m                 # app + Caddy
aws logs tail /cloudpulse/dpaste --since 1h --filter-pattern "migrations"
```

### Manual rollback to a specific release [verified] (automatic rollback verified; manual uses the same script)

List releases, then deploy an older tag through SSM:

```powershell
aws ecr describe-images --repository-name cloudpulse --query "sort_by(imageDetails,&imagePushedAt)[].imageTags[0]" --output text
# then send-command with: /opt/cloudpulse/deploy.sh <older-tag>
```

### Snippet cleanup [verified]

Runs daily via `cloudpulse-cleanup.timer`. Run it now: `systemctl start cloudpulse-cleanup.service` (through SSM), then `journalctl -u cloudpulse-cleanup.service -n 5`.

### SSH (break-glass) [verified]

Only from the IP in `allowed_ssh_cidr`, with the Academy key (`labsuser.pem`, permissions restricted with `icacls`):

```powershell
ssh -i "$HOME\.ssh\labsuser.pem" "ec2-user@$(terraform -chdir=terraform output -raw instance_public_ip)"
```

---

## 6. Monitoring stack (local) [verified]

```powershell
cd monitoring
powershell -ExecutionPolicy Bypass -File set-production-target.ps1
docker compose up -d --build
cd ..
```

- Grafana: http://localhost:3000 (admin / `GRAFANA_ADMIN_PASSWORD`, default `cloudpulse-local`) -> Dashboards -> CloudPulse
- Prometheus: http://localhost:9090 (targets, alerts)
- The CloudWatch panels use `~/.aws` (read-only mount) and stop working when the lab session credentials expire.

---

## 7. Teardown [not yet verified]

```powershell
terraform -chdir=terraform plan -destroy -out=destroy.tfplan
terraform -chdir=terraform apply destroy.tfplan
```

`force_delete = true` on the ECR repository removes its images. The state bucket is not managed by Terraform: empty all object **versions** and delete it manually afterwards, only once the state is no longer needed.