# Accepted Risks (POA&M-style)

This is the list of security findings I chose **not** to fix, and why. In an RMF package these would be
Plan of Action & Milestones (POA&M) items or risk acceptances signed by the system owner.
Every exception is written down here and in the code, never silently ignored.

- **System:** cloud-portfolio-app (dev), AWS us-east-1
- **Owner:** Fabron Kelly
- **Last reviewed:** 2026-11-11
- **Security Hub score (NIST 800-53 Rev 5):** 84% (246/297) at the first scan, 88% (261/297) after the account cleanup, 90% (266/297) after the 2026-11-11 fixes

## 1. AWS Security Hub (NIST 800-53 Rev 5) findings

| Control | Severity | NIST | Why it is accepted | Compensating control / plan |
|---|---|---|---|---|
| IAM.6 Hardware MFA for root | Critical | IA-2(1), IA-2(2) | A hardware key costs money for a personal lab account | Root has virtual (app) MFA, has no access keys, and is not used day to day; all work uses IAM Identity Center SSO with 8-hour sessions |
| KMS.3 KMS key pending deletion | Critical | SC-12, SC-28 | Old `tech-challenge-2-eks` key from a finished project, scheduled for deletion on purpose | Clears automatically when deletion completes on 2026-11-28 |
| EC2.10, EC2.55, EC2.56, EC2.57, EC2.58, EC2.60 VPC interface endpoints | Medium | SC-7, AC-4 | Each interface endpoint costs about $7/month per AZ per VPC (well over $100/month for all of them) | App traffic to AWS leaves through a NAT gateway over TLS; the default VPC runs only temporary Packer builds. Findings for the deleted `1pu-vpc` age out automatically |
| EC2.6 VPC flow logs on the default VPC | Medium | AU-12, SI-4 | The default VPC runs nothing except short Packer builds | The portfolio VPC has flow logs (365 days); CloudTrail records every API call |
| S3.7, S3.9, S3.11, S3.15, S3.17 extra S3 controls (replication, access logs, event notifications, Object Lock, KMS) | Low/Medium | AU-9, CP-9, SC-28 | Single-region lab; adds cost and complexity | All buckets: versioning, encryption, Block Public Access, TLS-only bucket policy, lifecycle rules. The CloudTrail bucket uses a customer-managed KMS key |
| RDS.5, RDS.8, RDS.11, RDS.26, RDS.6, RDS.23, RDS.9 dev database settings | Low/Medium | CP-9, CP-10, AU-12, SI-4 | Dev must stay cheap and destroyable (single AZ, 1-day backups, no deletion protection) | Prod settings turn on Multi-AZ, deletion protection and longer backups; the database is encrypted, private-subnet only, and its password lives in Secrets Manager |
| ELB.1, ELB.5, ELB.6, ELB.16 load balancer (HTTPS, access logs, deletion protection, WAF) | Medium | SC-8, AU-12, SC-7 | No custom domain yet, so no TLS certificate; WAF and access logs add cost | Next step: Route 53 domain + ACM certificate + HTTPS redirect, then AWS WAF |
| ECR.2, ECR.5, ECS.12 registry and cluster extras | Medium | CM-2, SC-28, SI-4 | Immutable tags block the first "latest" deploy; KMS and Container Insights add cost | The pipeline deploys commit-SHA tags; images are scanned with Trivy and ECR scan on push; CPU/memory alarms watch the service |
| SNS.1 alert topic KMS encryption | Medium | SC-28 | CloudWatch alarms cannot publish to a topic encrypted with the AWS-managed key | Topic carries alarm text only, no sensitive data |
| Macie.1 Amazon Macie | Medium | SI-4, RA-5 | Paid service; no sensitive data is stored in S3 | Buckets hold only logs and Terraform state |

### Fixed on 2026-11-11 (no longer accepted)

| Control | Fix |
|---|---|
| CloudTrail.2 | CloudTrail logs encrypted with a customer-managed KMS key with yearly rotation |
| CloudTrail.5 | Trail also delivered to CloudWatch Logs (`/aws/cloudtrail/portfolio-trail`, 365 days, KMS) |
| CloudWatch.16 | App and VPC flow log groups keep logs 365 days (was 14) |
| ECS.5 | App container runs with a read-only root filesystem; gunicorn uses `/dev/shm` |
| EC2.15 | Auto-assign public IP turned off on the default VPC subnets; unused `1pu-vpc` deleted |
| S3.1 (2026-11-12) | S3 Block Public Access turned on for the whole account |

## 2. DISA RHEL 9 STIG items left open in the Packer image

| Item | Why it is accepted |
|---|---|
| FIPS mode | Needs a reboot during the build; planned as a next step |
| GRUB2 bootloader password | A password must not be baked into a shared image; it would be set per instance at launch |
| Separate partitions (`/var`, `/var/log`, `/tmp`, `/home`) | Needs a custom disk layout instead of the stock AWS AMI |
| SSSD certificate mapping (CAC/PIV login) | No smart-card infrastructure in a lab account |
| Multiple DNS servers | AWS VPC provides one DNS resolver (Route 53 Resolver) |

## 3. Checkov (Terraform scan) skips

Each skip is also written next to the resource in the code (`#checkov:skip=ID:reason`).

| File | Check | Reason |
|---|---|---|
| `bootstrap/main.tf` | CKV_AWS_144 | Cross-region replication is not needed for a single-region portfolio project |
| `bootstrap/main.tf` | CKV_AWS_18 | Access logging for the state bucket is out of scope (CloudTrail records API access) |
| `bootstrap/main.tf` | CKV2_AWS_62 | No event notifications needed for the state bucket |
| `bootstrap/main.tf` | CKV_AWS_145 | SSE-S3 (AES256) is sufficient; a customer-managed KMS key adds cost |
| `modules/compute/main.tf` | CKV_AWS_91 | ALB access logs are out of scope for this project |
| `modules/compute/main.tf` | CKV2_AWS_28 | AWS WAF adds cost; listed in the README as a next step |
| `modules/compute/main.tf` | CKV2_AWS_20 | Cannot redirect HTTP to HTTPS without a certificate (next step: ACM + Route 53) |
| `modules/compute/main.tf` | CKV_AWS_150 | Dev must be destroyable; deletion protection is set by var.deletion_protection |
| `modules/compute/main.tf` | CKV_AWS_378 | Traffic from the ALB to containers stays inside the private VPC network |
| `modules/compute/main.tf` | CKV_AWS_2 | No custom domain, so no TLS certificate yet; HTTPS via ACM is the documented next step |
| `modules/compute/main.tf` | CKV_AWS_103 | Same as above (TLS policy applies to HTTPS listeners) |
| `modules/compute/main.tf` | CKV2_AWS_20 | Cannot redirect HTTP to HTTPS without a certificate |
| `modules/compute/main.tf` | CKV_AWS_158 | Default CloudWatch encryption is used; a customer-managed KMS key adds cost |
| `modules/compute/main.tf` | CKV_AWS_65 | Container Insights adds per-metric cost; service CPU/memory metrics and alarms are used instead |
| `modules/database/main.tf` | CKV_AWS_118 | Enhanced monitoring adds cost; basic CloudWatch metrics + alarms are used instead |
| `modules/database/main.tf` | CKV_AWS_353 | Performance Insights is not needed at this scale |
| `modules/database/main.tf` | CKV_AWS_354 | Performance Insights is disabled, so no PI KMS key |
| `modules/database/main.tf` | CKV_AWS_157 | Multi-AZ is enabled in prod via var.multi_az; dev stays single-AZ to save cost |
| `modules/database/main.tf` | CKV_AWS_293 | Deletion protection is enabled in prod via var.deletion_protection; dev must be destroyable |
| `modules/database/main.tf` | CKV2_AWS_30 | Query logging is not needed; postgresql logs are exported to CloudWatch |
| `modules/database/main.tf` | CKV2_AWS_60 | Copy-tags-to-snapshot is enabled |
| `modules/ecr/main.tf` | CKV_AWS_51 | Mutable tags allow a moving "latest" tag for the first deploy; the pipeline deploys immutable commit-SHA tags |
| `modules/ecr/main.tf` | CKV_AWS_136 | AES256 encryption is used; a customer-managed KMS key adds cost |
| `modules/monitoring/main.tf` | CKV_AWS_26 | CloudWatch alarms cannot publish to a topic encrypted with the AWS-managed SNS key; a customer-managed key adds cost |
| `modules/network/main.tf` | CKV_AWS_394 | The module slices the first var.az_count zones, so new AZs never change the result |
| `modules/network/main.tf` | CKV_AWS_158 | Default CloudWatch encryption is used; a customer-managed KMS key adds cost |
| `modules/security/main.tf` | CKV2_AWS_5 | Attached in the compute/database modules (Checkov cannot see across modules) |
| `modules/security/main.tf` | CKV_AWS_260 | The public load balancer must accept HTTP until a custom domain + TLS certificate is added |
| `security-baseline/cloudtrail.tf` | CKV_AWS_144 | Cross-region replication is not needed for a single-region portfolio project |
| `security-baseline/cloudtrail.tf` | CKV_AWS_18 | Access logging for the log bucket itself is out of scope |
| `security-baseline/cloudtrail.tf` | CKV2_AWS_62 | No event notifications needed for the log bucket |
| `security-baseline/cloudtrail.tf` | CKV_AWS_252 | SNS notifications for each new log file are not needed |
| `security-baseline/security_services.tf` | CKV2_AWS_3 | Single AWS account with no AWS Organization |
| `security-baseline/security_services.tf` | CKV_AWS_144 | Cross-region replication is not needed for a single-region portfolio project |
| `security-baseline/security_services.tf` | CKV_AWS_145 | SSE-S3 (AES256) is used; a customer-managed KMS key is a planned improvement |
| `security-baseline/security_services.tf` | CKV_AWS_18 | Access logging for the log bucket itself is out of scope |
| `security-baseline/security_services.tf` | CKV2_AWS_62 | No event notifications needed for the log bucket |
