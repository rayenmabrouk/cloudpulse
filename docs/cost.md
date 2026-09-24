# Cost analysis

Last updated: 2026-09-24

The project runs in an **AWS Academy Learner Lab** with a **$50 credit budget**. Academy stops the EC2 instance when a lab session ends, so the real spend is far below a 24/7 estimate.

Actual spend is shown in Vocareum ("Used $X of $50").

## What a 24/7 month would cost (estimate)

Estimates use public **us-east-1 on-demand** prices at the time of writing; check the [AWS pricing pages](https://aws.amazon.com/pricing/) for current values.

| Resource | Basis | ~ USD / month |
|---|---|---|
| EC2 t3.micro | $0.0104 / hour x 730 h | 7.59 |
| Public IPv4 address | $0.005 / hour x 730 h | 3.65 |
| EBS gp3, 20 GB | $0.08 / GB-month | 1.60 |
| EC2 detailed monitoring | 7 metrics x $0.30 | 2.10 |
| CloudWatch alarms | 3 x $0.10 | 0.30 |
| CloudWatch custom metric (5xx metric filter) | 1 x $0.30 | 0.30 |
| CloudWatch Logs | < 1 GB ingested, 7-day retention | < 0.50 |
| ECR storage | 10 images kept by the lifecycle policy, ~0.8 GB x $0.10 | < 0.10 |
| S3 state bucket | a few KB, versioned | ~0 |
| S3 backup bucket | 14 daily compressed SQLite backups, KB-sized | ~0 |
| SNS email notifications (optional) | within the free tier (1,000 emails / month) | 0 |
| SSM Parameter Store | standard parameter | 0 |
| Data transfer out | a pastebin demo, well under 1 GB | < 0.10 |
| **Total** | | **~ $16** |

GitHub Actions minutes are free for public repositories. Let's Encrypt certificates and sslip.io DNS are free.

## Deliberate cost decisions

| Not used | Typical monthly cost | Why skipped | Production alternative |
|---|---|---|---|
| Application Load Balancer | ~$16+ | single instance; Caddy terminates TLS | ALB + ACM certificate |
| NAT gateway | ~$32+ | instance sits in a public subnet | private subnet + NAT or VPC endpoints |
| RDS | ~$12+ (smallest) | dpaste is designed for SQLite | RDS PostgreSQL, stateless app tier |
| Route 53 hosted zone + domain | ~$0.50 + domain | sslip.io hostname | Route 53 + Elastic IP |
| EKS | ~$73 control plane | far beyond the need | EKS or ECS Fargate when there are several services |
| Customer-managed KMS keys | $1 / key | AWS-managed encryption is already on | CMKs where key policy control is required |

## Where the money would go first

Detailed monitoring (~$2.10) was enabled on purpose: 1-minute metrics make the CPU alarm react faster. On a tight budget it is the first thing to turn off, followed by the public IPv4 charge (only avoidable with a load balancer or IPv6).