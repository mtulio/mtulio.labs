---
paths:
  - "docs/**/*.md"
  - "labs/**/*"
  - "hack/**/*"
---

# Sensitive Data Prevention

Before committing or approving any file, scan for these patterns and flag them:

## Must Block (never commit)
- AWS access key IDs (`AKIA...`, 20 chars alphanumeric)
- AWS secret access keys (40 chars base64-like)
- AWS session tokens
- Bearer tokens, JWTs, or OIDC tokens (base64 encoded strings > 40 chars)
- Private SSH keys (`-----BEGIN ... PRIVATE KEY-----`)
- Kubeconfig files with embedded credentials or tokens
- `.env` files with populated secrets
- Pull secret JSON blobs containing `auth` fields with base64 credentials
- GPG private keys
- Passwords or passphrases in plaintext

## Must Redact (replace with `[redacted]` or variable references)
- AWS account IDs (12-digit numbers in ARN context)
- IAM role ARNs containing account IDs
- S3 bucket names tied to real infrastructure (use `${BUCKET_NAME}` pattern)
- OIDC provider URLs with account-specific paths
- Cluster-specific hostnames or API endpoints
- Email addresses (unless public/intentional)
- IP addresses of real infrastructure

## Acceptable Patterns
- Environment variable references (`$AWS_SHARED_CREDENTIALS_FILE`, `${PULL_SECRET_FILE}`)
- Generic example values (`example.com`, `123456789012`)
- Values already marked as `[redacted]`
- Public registry references (`quay.io`, `registry.ci.openshift.org`)
- RFC 1918 private ranges used as examples (`10.x`, `172.16.x`, `192.168.x`)

## When Reviewing PRs
1. Grep for AWS key patterns: `AKIA[0-9A-Z]{16}`
2. Check for inline tokens or passwords in code blocks
3. Verify all ARNs use `[redacted]` for account IDs
4. Flag any hardcoded file paths under `/home/` that contain usernames other than generic ones
5. Check for kubeconfig content with embedded certificates or tokens
