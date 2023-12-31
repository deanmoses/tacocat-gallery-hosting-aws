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
- Node.js 18 or higher

## Install

- Clone this project from github
- There's no dependencies to install and no code to build

## Deploy to dev

```bash
sam validate # validates any changes you've made to template.yaml
sam build # transforms the template
sam deploy # deploys the infrastructure to AWS
```

Then go to the project that builds the actual website assets and deploy it to this infrastructure.

## Deploy to prod

```bash
sam deploy --config-env prod
```

This will change the name of the stack to `tacocat-gallery-website-hosting-prod` (look in `samconfig.toml` for how).  Changing the name of the stack will create an entirely new stack with different resources.

## Cleanup

To entirely delete the dev infrastructure from AWS:

```bash
sam delete
```

⚠️ :warning: There's a slight chance this _might_ delete the prod infrastructure, though I _think_ it'll hit dev.