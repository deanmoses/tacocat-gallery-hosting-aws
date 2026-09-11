# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an AWS SAM infrastructure-only project that defines hosting for the Tacocat photo gallery SPA. It contains no application code—just CloudFormation/SAM templates that provision AWS resources. The actual website is deployed separately to this infrastructure.

## Commands

```bash
npm install         # Install husky (first time setup)
sam validate        # Validate template.yaml syntax
./scripts/lint.sh   # Full lint suite (cfn-lint, CloudFront Function JS, shellcheck, actionlint)
sam build           # Transform the SAM template
sam sync            # Deploys to dev / staging (hosts the files of staging-pix.tacocat.com)

```

Production deployments are done via GitHub Actions (manual trigger).

## Architecture

**S3 + CloudFront static SPA hosting:**

- S3 bucket stores static assets (HTML, CSS, JS, images)
- CloudFront distribution serves content with HTTPS
- Origin Access Control (OAC) restricts S3 access to CloudFront only
- Custom error responses return index.html for SPA routing (404/403 → 200 with index.html)
- Access logs delivered to a dedicated S3 bucket, expiring after 90 days (see Observability)
- `X-Robots-Tag` and `tdm-reservation` response headers opt out of indexing and AI training
- HSTS (1 year, `includeSubDomains`, no preload), `nosniff`, `Referrer-Policy`, `X-Frame-Options: DENY` and `Permissions-Policy`. `includeSubDomains` binds `img.`/`api.`/`auth.` — a new subdomain must be HTTPS from day one

**Cache behaviors:**

- `/_app/immutable/*`: 1-year cache with immutable headers (SvelteKit build output)
- `/robots.txt`: Served by CloudFront Function
- Default: Standard CloudFront caching

**Environments:**

- Dev stack: `tacocat-gallery-website-hosting-dev` → staging-pix.tacocat.com
- Prod stack: `tacocat-gallery-website-hosting-prod` → pix.tacocat.com

## Key Files

- `template.yaml` - All AWS resources (S3, CloudFront, policies, inline CloudFront Function for robots.txt, access log delivery)
- `samconfig.toml` - SAM CLI config with dev/prod parameters

## CI/CD

- **Linting**: `scripts/lint.sh` is the single lint entry point, run by both the pre-commit hook and CI so the two cannot drift. It covers cfn-lint (`sam validate --lint`), the inline CloudFront Function's JavaScript, shellcheck on `*.sh` plus the hook, and actionlint on the workflows. A missing linter only warns locally, but fails in CI (`CI` is set) — a check CI skips silently is a check that no longer exists.
- **Pre-commit hooks**: Husky runs `scripts/lint.sh` and gitleaks (secret scanning) on commit. Husky invokes hooks with `sh -e`, so `.husky/pre-commit` must stay POSIX.
- **CI workflow**: On PR and push to main, runs lint, build, and changeset validation. On push to main, also deploys to staging and runs integration tests.
- **Production deploy**: Manual workflow dispatch from GitHub Actions. Deploys to prod, runs integration tests, creates a release tag (YYYYvN format), and generates release notes.

## Observability

Logging is configured through CloudWatch Logs delivery resources in `template.yaml`, not the distribution's own `Logging` block, so `aws cloudfront get-distribution-config` and the console both report logging disabled while logs are flowing — `aws logs describe-delivery-sources` is what answers that. Delivery lags requests by ten minutes to a few hours.
