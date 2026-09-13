# Account setup deployed by hand

Things that must exist in the AWS account before CI can run, and so are deployed by hand rather than by CI.

## GitHub Actions roles

[github-oidc.yaml](github-oidc.yaml) creates the three roles the workflows assume (pull request, main, prod) and the CloudFormation service role that does the actual deploying. The template's header comment explains how they fit together. The GitHub OIDC identity provider they trust is account-wide and lives in the [aws-bootstrap](https://github.com/deanmoses/aws-bootstrap) repo.

Deploy or update with admin credentials:

```bash
aws cloudformation deploy --template-file infra/github-oidc.yaml --stack-name tacocat-gallery-website-hosting-cicd --capabilities CAPABILITY_NAMED_IAM
```

The role ARNs are stable, so the workflows and `samconfig.toml` reference them directly. If you rename a role, update `.github/workflows/*.yml` and the `role_arn` entries in `samconfig.toml` to match.

There are no AWS secrets in the GitHub repository. A workflow job gets a short-lived credential by presenting its OIDC token, and which role it may assume is decided by the token's `sub` claim: pull requests, runs on `main`, or the `prod` GitHub environment. The `prod` environment is configured in the repository settings to require a reviewer's approval and to deploy only from protected branches.

## GitHub repository settings

Settings CI relies on that live in the repository's settings rather than in a file here:

- `prod` environment: requires a reviewer and deploys only from protected branches. The prod AWS role trusts jobs in this environment alone.
- Branch protection on `main`: pull requests only, and the `merge-ok` check must pass.
- Actions: only GitHub-owned, verified-creator, `aws-actions/*`, `dorny/paths-filter` and `softprops/action-gh-release` actions may run, and every action must be pinned to a commit SHA. The pins are moved by hand, on purpose: there is no Dependabot, because an automatic bump is a change nothing here tests well enough to trust.
- Secret scanning and push protection are on. The pre-commit gitleaks scan only runs where gitleaks is installed; push protection is the backstop.

## Production stack

Termination protection is enabled by hand on `tacocat-gallery-website-hosting-prod`. The prod CI role cannot delete stacks anyway; this guards against a slip with admin credentials.

```bash
aws cloudformation update-termination-protection --enable-termination-protection --stack-name tacocat-gallery-website-hosting-prod
```
