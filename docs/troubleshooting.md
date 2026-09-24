# Troubleshooting

Last updated: 2026-09-23

Every problem below actually happened while building CloudPulse. Each entry gives the symptom, the root cause and the fix.

## Windows / PowerShell

### 1. `terraform init`: "Invalid character encoding"
- **Symptom:** `Invalid character encoding` / `Unterminated template string` in `outputs.tf`.
- **Cause:** an em-dash in a description was written by PowerShell in a legacy encoding, and `<ip>` inside a string looked like a template.
- **Fix:** keep `.tf` files ASCII-only.

### 2. Terraform / AWS CLI: "No valid credential sources found"
- **Symptom:** credentials file present but not read.
- **Cause:** `Set-Content -Encoding UTF8` in Windows PowerShell 5 writes a **byte order mark**; the AWS SDK cannot parse the first line.
- **Fix:** `[System.IO.File]::WriteAllText($path, $content)` (UTF-8 without BOM).

### 3. `docker login` to ECR: `400 Bad Request`
- **Cause:** piping `aws ecr get-login-password` into `docker login` in PowerShell 5 re-encodes the token.
- **Fix:** run the pipe in cmd: `cmd /c "aws ecr get-login-password | docker login --username AWS --password-stdin <registry>"`.

### 4. AWS CLI: `'charmap' codec can't encode character`
- **Cause:** remote output contained an emoji (dpaste's startup banner) and the CLI prints with the Windows console code page; `PYTHONUTF8` is ignored by the bundled Python.
- **Fix:** strip non-ASCII on the server: `... | tr -cd '\11\12\40-\176'`.

### 5. `terraform plan` wants to modify `user_data` although nothing changed
- **Symptom:** in-place update of the instance (which would restart it) after switching Git branches.
- **Cause:** `user_data.sh` switched between CRLF and LF line endings; Terraform hashes the bytes.
- **Fix:** `.gitattributes` with `*.sh text eol=lf` (and `*.tf`, `*.hcl`), then a one-time apply. Lesson learned: the repository already had a `.gitattributes`; **append** to existing config files instead of overwriting them.

### 6. AWS CLI: "You must specify a region"
- **Fix:** create `~/.aws/config` with `region = us-east-1`.

## AWS Academy

### 7. Console: `explicit deny ... policy/voc-cancel-cred`
- **Cause:** a console tab opened in a previous lab session; Vocareum revokes older sessions.
- **Fix:** close all console tabs and reopen the console from the Vocareum AWS link.

### 8. OIDC for GitHub Actions: `AccessDenied` on `iam:CreateOpenIDConnectProvider`
- **Cause:** the Learner Lab does not allow creating IAM identity providers or roles.
- **Fix / trade-off:** use the lab's short-lived session credentials as GitHub secrets, refreshed by `scripts/refresh-github-aws-secrets.ps1` each session.

## Terraform

### 9. `InvalidBlockDeviceMapping: Volume of size 20GB is smaller than snapshot ... expect size >= 30GB`
- **Cause:** the AMI filter `al2023-ami-*-x86_64` also matched `al2023-ami-ecs-hvm-...` (ECS-optimized, 30 GB snapshot) and `most_recent` picked it. The login banner said "Amazon Linux 2023 (ECS Optimized)".
- **Fix:** filter `al2023-ami-2023.*-x86_64`. The replacement plan also updated both CloudWatch alarms (their `InstanceId` dimension), which is why plans are reviewed.

### 10. Checkov passes but ignores some files
- **Symptom:** `Parsing errors: 3` and CloudWatch resources never scanned.
- **Cause:** three files contained byte `0x97` (a Windows-1252 em-dash) in comments. Terraform tolerated it; Checkov could not parse the files and skipped them.
- **Fix:** convert every `.tf` file to ASCII.

## Application / deployment

### 11. `403 Forbidden - CSRF verification failed` when creating a snippet
- **Cause:** dpaste sets `CSRF_COOKIE_SECURE = True` and `SESSION_COOKIE_SECURE = True`. Over plain HTTP the browser drops these cookies. It worked locally because browsers treat `localhost` as secure.
- **Fix:** serve over HTTPS (Caddy + Let's Encrypt on an sslip.io hostname). dpaste already sets `SECURE_PROXY_SSL_HEADER`, so it trusts `X-Forwarded-Proto` from the proxy. Disabling the secure cookies was rejected.

### 12. Snippets would have been lost on every redeploy
- **Cause:** the deploy script mounted the volume at `/db`, but the image's `DATABASE_URL` is `sqlite:////data/dpaste.sqlite`.
- **Fix:** read the path from the image (`docker image inspect --format '{{json .Config.Env}}'`) and mount at `/data`. Caught before the first deploy.

### 13. ECR scan status `None`, three entries for one image
- **Cause:** Docker Buildx adds a provenance attestation, so the push is an image index, which ECR basic scanning does not handle.
- **Fix:** build with `--provenance=false --sbom=false`.

### 14. `docker login` warning: password stored unencrypted in `/root/.docker/config.json`
- **Fix:** Amazon ECR credential helper; `config.json` now only contains `credHelpers`.

### 16. Terraform pipeline: `Saved plan is stale`
- **Symptom:** the approved Apply job failed immediately: "The given plan file can no longer be applied because the state was changed by another operation after the plan was created."
- **Cause:** while the apply was waiting for approval, a local `terraform apply -refresh-only` updated the state (new public IP after a lab restart). The pipeline applies only the exact plan that was reviewed, so it refused a plan built from older state.
- **Fix:** re-run the workflow (`gh workflow run terraform.yml --ref master`) to get a fresh plan, review it, approve it. Lesson: no local state-changing Terraform commands while a pipeline apply is pending.

### 17. `AccessDenied ... s3:GetBucketObjectLockConfiguration ... explicit deny in a service control policy`
- **Symptom:** the apply created the backup bucket, then failed reading it back; every later `plan` failed with the same error.
- **Cause:** the AWS provider reads a bucket's object-lock configuration whenever it manages an `aws_s3_bucket` resource, and the AWS Academy organization SCP denies that call. The state bucket never hit this because it was created with the AWS CLI.
- **Fix:** removed the bucket resource from state (`terraform state rm module.compute.aws_s3_bucket.backups`, which leaves the bucket in AWS), create the bucket in `scripts/bootstrap-tfstate.ps1`, and keep managing its settings in Terraform (versioning, encryption, lifecycle, policy and public access block resources do not read object lock).

## Monitoring

### 15. cAdvisor running but container panels empty
- **Symptom:** only one anonymous series; logs show `failed to identify the read-write layer ID ... layerdb/mounts/...: no such file or directory`.
- **Cause:** Docker Desktop uses the containerd image store; cAdvisor v0.49 expects the classic `overlay2` layout.
- **Fix:** removed cAdvisor; the Grafana dashboard shows production EC2 CPU and network from CloudWatch instead.

### Grafana: "Invalid username or password"
- **Fix:** `docker exec cloudpulse-grafana grafana cli admin reset-admin-password <password>`. Repeated failures trigger a short lockout.
