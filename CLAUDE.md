# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an AWS SAM infrastructure-only project that defines hosting for the Tacocat photo gallery SPA. It contains no application code—just CloudFormation/SAM templates that provision AWS resources. The actual website is deployed separately to this infrastructure.

## Commands

```bash
npm install         # Install husky (first time setup)
sam validate        # Validate template.yaml syntax
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

**Cache behaviors:**
- `/_app/immutable/*` - 1-year cache with immutable headers (SvelteKit build output)
- `/robots.txt` - Intercepted by CloudFront Function to return 404
- Default - Standard CloudFront caching

**Environments:**
- Dev stack: `tacocat-gallery-website-hosting-dev` → staging-pix.tacocat.com
- Prod stack: `tacocat-gallery-website-hosting-prod` → pix.tacocat.com

## Key Files

- `template.yaml` - All AWS resources (S3, CloudFront, policies, inline CloudFront Function for robots.txt)
- `samconfig.toml` - SAM CLI config with dev/prod parameters

## CI/CD

- **Pre-commit hooks**: Husky runs sam validate and gitleaks (secret scanning) on commit.
- **CI workflow**: On PR and push to main, runs SAM validate, build, and changeset validation. On push to main, also deploys to staging and runs integration tests.
- **Production deploy**: Manual workflow dispatch from GitHub Actions. Deploys to prod, runs integration tests, creates a release tag (YYYYvN format), and generates release notes.

