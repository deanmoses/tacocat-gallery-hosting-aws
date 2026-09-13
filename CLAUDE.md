# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an AWS SAM infrastructure-only project that defines hosting for the Tacocat photo gallery SPA. It contains no application code, just a CloudFormation/SAM template that provision AWS resources. The actual website is deployed separately to this infrastructure.  The ecosystem is described in the `tacocat-gallery-sveltekit` project's `docs/Ecosystem.md`.

## Commands

```bash
npm install         # Install husky (first time setup)
sam validate        # Validate template.yaml syntax
./scripts/lint.sh   # Full lint suite (cfn-lint, CloudFront Function JS, shellcheck, actionlint)
sam build           # Transform the SAM template
sam sync            # Deploys to dev / staging (hosts the files of staging-pix.tacocat.com)

```

## Architecture

### S3 + CloudFront static SPA hosting

- S3 bucket stores static assets (HTML, CSS, JS, images)
- CloudFront distribution serves content with HTTPS
- Origin Access Control (OAC) restricts S3 access to CloudFront only
- Custom error responses return index.html for SPA routing (404/403 → 200 with index.html)
- Access logs delivered to a dedicated S3 bucket, expiring after 90 days (see Observability)
- `X-Robots-Tag` and `tdm-reservation` response headers opt out of indexing and AI training
- HSTS (1 year, `includeSubDomains`, no preload), `nosniff`, `Referrer-Policy`, `X-Frame-Options: DENY` and `Permissions-Policy`. `includeSubDomains` binds `img.`/`api.`/`auth.` — a new subdomain must be HTTPS from day one

### Cache behaviors

- `/_app/immutable/*`: 1-year cache with immutable headers (SvelteKit build output)
- `/robots.txt`: Served by CloudFront Function
- Default: Standard CloudFront caching

### Environments

- Dev stack: `tacocat-gallery-website-hosting-dev` → staging-pix.tacocat.com
- Prod stack: `tacocat-gallery-website-hosting-prod` → pix.tacocat.com

## Key Files

- `template.yaml` - All AWS resources (S3, CloudFront, policies, inline CloudFront Function for robots.txt, access log delivery)
- `samconfig.toml` - SAM CLI config with dev/prod parameters
- `infra/github-oidc.yaml` - IAM roles CI assumes and the CloudFormation service role that deploys the stacks. Deployed by hand, see `infra/README.md`

## CI/CD

- **Pre-commit hooks**: Husky runs `scripts/lint.sh` and gitleaks secret scanning on commit.
- **CI workflow**: on PR and push to main, runs lint, build, and changeset validation. On push to main, also deploys to staging and runs integration tests.
- **Production deploy**: production deployments are done by manually triggering a GitHub Action.  Waits for approval in the `prod` GitHub environment, deploys to prod, runs integration tests, creates a release tag and generates release notes.
- **CI credentials**: no AWS keys are stored in GitHub. Each job exchanges its GitHub OIDC token for a short-lived IAM role scoped to what that job does (pull request, main, prod), see `infra/README.md`.

## Observability

Logging is configured through CloudWatch Logs delivery resources in `template.yaml`, not the distribution's own `Logging` block, so `aws cloudfront get-distribution-config` and the console both report logging disabled while logs are flowing — `aws logs describe-delivery-sources` is what answers that. Delivery lags requests by ten minutes to a few hours.
