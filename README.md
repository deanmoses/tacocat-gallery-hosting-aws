# tacocat-gallery-hosting-aws

This defines the hosting infrastructure for the static files of the Tacocat photo gallery website single page application (SPA) on AWS.

It does NOT contain the actual website itself.  That's a separate project that deploys its contents to this infrastructure.

## Key services

The SPA's static file assets are stored in an Amazon AWS S3 Bucket fronted by CloudFront. 

## SAM
This project uses the Amazon AWS Serverless Application Model (SAM).  You can see all the assets defined in the standard `template.yaml` file.

It's a little weird to use SAM because there's no code, no lambdas.  I'm using it because:
 - At some point this project might contain lambdas
 - Since every other project in the system uses SAM, it's easier to make them all similar

## Prerequisites

- The AWS Serverless Application Model Command Line Interface (SAM CLI)
- Node.js

## Install

- Clone this project from github
- Install deps:

```bash
npm install
```

## Develop
The main 'development' is editing the AWS infrastructure (`template.yaml`):

When you make changes to the template:
```bash
sam validate        # Validates any changes you've made to the SAM template.yaml
sam build           # Transform the template
```

## Deploying to dev

Dev/staging hosts the files of <https://staging-pix.tacocat.com>.  

To deploy:
```bash
sam sync          # Re-deploy the stack to dev/staging
```

After deploying, you can either:
- Hit <https://staging-pix.tacocat.com> and validate that the web app is still being served correctly.
- Go the project that builds the actual website assets and deploy it to this infrastructure.
- Run integration tests:

```bash
./scripts/integration-tests.sh # Run integration tests against dev/staging
```

There are no unit tests.

## Committing & PRs
You must submit a PR to change main.

- Committing will:
  - Run precommit checks, like a secret scanner, linter, and SAM template validation.
- Merging a PR will:
  -  Deploy to dev / staging
  -  Run integration tests

## Deploy to prod

Prod hosts the files of <https://pix.tacocat.com>

- Use the `Deploy to Production` GitHub Action to deploy to prod.  This will:
  - Deploy to prod
  - Run integration tests
  - Create a release tag and release on GitHub 
- Then you can either:
  - Hit <https://pix.tacocat.com> and validate that the web app is still being served correctly.
  - Go to the project that builds the actual website assets and deploy it to this infrastructure.
