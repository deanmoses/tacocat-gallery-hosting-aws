# Account setup deployed by hand

Things that must exist in the AWS account before CI can run, and so are deployed by hand rather than by CI.

## GitHub Actions roles

[github-oidc.yaml](github-oidc.yaml) creates the three roles the workflows assume (pull request, main, prod) and the two CloudFormation service roles, one per environment, that do the actual deploying. The template's header comment explains how they fit together. The GitHub OIDC identity provider they trust is account-wide and lives in the [aws-bootstrap](https://github.com/deanmoses/aws-bootstrap) repo.

Deploy or update with admin credentials:

```bash
aws cloudformation deploy --template-file infra/github-oidc.yaml --stack-name tacocat-gallery-website-hosting-cicd --capabilities CAPABILITY_NAMED_IAM
```

The role ARNs are stable, so the workflows and `samconfig.toml` reference them directly. If you rename a role, update `.github/workflows/*.yml` and the `role_arn` entries in `samconfig.toml` to match.

There are no AWS secrets in the GitHub repository. A workflow job gets a short-lived credential by presenting its OIDC token, and which role it may assume is decided by the token's `sub` claim: pull requests, runs on `main`, or the `prod` GitHub environment. The `prod` environment is configured in the repository settings to deploy only from protected branches, of which `main` is the only one. It has no required reviewer: the pull request into `main` is the review.

## Claude Code on the web

The same template gives a cloud session what it needs in this project: deploy the dev stack, and read both environments' CloudFront access logs out of the bucket they are delivered to. That is the reach the `main` CI role has, plus the logs no CI job needs. Prod logs are included, because an incident is when you most want them and reading a log changes nothing. Deploying to prod is out of reach under an explicit `Deny`.

It also grants the three `logs:DescribeDeliver*` calls. Logging here is configured through delivery resources rather than the distribution's own `Logging` block, so the console and `get-distribution-config` both report it disabled while logs are flowing, and those calls are the only way to tell.

A session authenticates as one IAM user for the whole account, `tacocat-gallery-claude-code-cloud`, and that user is created by the [tacocat-gallery-sam](https://github.com/deanmoses/tacocat-gallery-sam) repo's `infra/`. **That stack has to be deployed before this one**, or the policy here has no user to attach to and the deploy fails. What the user may do in this project is still decided here: this template attaches its own managed policy, so the permissions live with the project rather than accumulating in another repo's template. The other Tacocat repos do the same.

One thing to watch when adding another repo to that arrangement: AWS allows ten managed policies per IAM user by default. This template attaches two of them.

## GitHub repository settings

Settings CI relies on that live in the repository's settings rather than in a file here:

- `prod` environment: deploys only from protected branches, no required reviewer. The prod AWS role trusts jobs in this environment alone.
- Branch protection on `main`: pull requests only, and the `merge-ok` check must pass. The check is bound to the GitHub Actions app, so a status of that name posted by any other integration does not count.
- Actions: only GitHub-owned, verified-creator, `aws-actions/*`, `dorny/paths-filter` and `softprops/action-gh-release` actions may run, and every action must be pinned to a commit SHA. The pins, and the SAM CLI version in `.github/actions/install-sam`, are moved by hand, on purpose: there is no Dependabot, because an automatic bump is a change nothing here tests well enough to trust.
- A tag ruleset blocks moving or deleting any tag, so release history stays intact. The release workflow only ever creates new ones.
- Secret scanning and push protection are on. The pre-commit gitleaks scan only runs where gitleaks is installed; push protection is the backstop.

## Production stack

Two guards are applied by hand. The prod CI role can call neither `UpdateTerminationProtection` nor `SetStackPolicy`, so a deploy cannot loosen them.

Termination protection stops the stack itself being deleted:

```bash
aws cloudformation update-termination-protection --enable-termination-protection --stack-name tacocat-gallery-website-hosting-prod
```

The stack policy in [prod-stack-policy.json](prod-stack-policy.json) stops an update from replacing or deleting the site bucket or the distribution, which is what a template edit to one of their immutable properties would otherwise do:

```bash
aws cloudformation set-stack-policy --stack-name tacocat-gallery-website-hosting-prod --stack-policy-body file://infra/prod-stack-policy.json
```

A deploy that has to replace one of them on purpose first sets a policy allowing `Update:*` on `*`, deploys, then reapplies this one.
