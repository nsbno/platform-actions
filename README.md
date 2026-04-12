# Vy Platform Actions

Shared GitHub Action "actions" and workflows that you can use for build, test and deploy!

Have a look at [.github/workflows](.github/workflows) and [.github/actions](.github/actions) 
for any useful tools you want to use.

Missing any workflows or suggestions for new ones? Feel free to open a PR 
or hit us up on Slack!

<!-- TOC -->
* [Quick start](#quick-start)
* [Upgrade guide](#upgrade-guide)
  * [platform-actions v2](#platform-actions-v2)
  * [What's new:](#whats-new)
* [Workflows](#workflows)
  * [Helpers](#helpers)
  * [Build, Test and Lint](#build-test-and-lint)
  * [Package](#package)
  * [Deploy](#deploy)
* [Note on Pull Requests](#note-on-pull-requests)
<!-- TOC -->

# Quick start

Have a look at [Build & Deployment Pipeline (confluence)](https://vygruppen.atlassian.net/wiki/x/lwAa8QE) 
for a detailed guide

**How to reference a workflow**:

```yaml
jobs:
  my-job:
    # Please pin your workflows to @v2 by default
    uses: nsbno/platform-actions/.github/workflows/my-job.yaml@v2
```

Please **pin the workflows and actions you use from platform-actions to `@v2`**.

We frequently update our workflows, and this saves you from continuously upgrading them
in all your projects. Additionally, it allows us to patch any bugs or vulnerabilities
in a single location and having it apply to all projects immediately.

There are of course some tradeoffs with it, and we do not recommend it for third-party workflows. 
If a non-working platform workflow is published it can break a lot of projects at the same time. However, we consider that the benefits
outweigh the risks, in this situation. We're strict on semantic versioning, and can quickly
introduce new patches or rollback.

# Upgrade guide

## platform-actions v2
This is a major update to platform-actions with several breaking changes.

### How to upgrade from v1
#### For all workflows
- Rename workflow: `deployment.all-environments.yml` to `deployment.all-environments-ecs.yml`.
- Remove `applications` parameter from all platform-actions workflows.
- For `package.docker.yml`, if using parameter `repo-name`, change it to `ecr-repo-name`.
- Use tag `@v2` for all `nsbno/platform-actions` workflows
  (Quick tip: do a global search for `.yml@v1` or `.yml@main` and replace with `.yml@v2`
- Remove `package.s3-static-files.yml` and replace with `package.s3.yml` with `artifact-path: "build/client"`

#### ECS
If your deployment target is ECS, use the latest 3.x version of terraform-aws-ecs-service
- Use the latest data source `vy_ecs_image`
- How to: https://github.com/nsbno/terraform-aws-ecs-service/releases/tag/3.0.0

#### Lambda
If your deployment target is Lambda, use the latest 2.x version of terraform-aws-lambda
- Use the latest data source `vy_lambda_artifact`
- How to: https://github.com/nsbno/terraform-aws-lambda/releases/tag/2.0.0

---

## What's new:
Please refer to the [release page](https://github.com/nsbno/platform-actions/releases) for the latest release notes.

# Workflows

Workflows are defined in `.github/workflows/` and can be used to automate tasks such as building, testing, packaging, and deploying code.

### Helpers
These are helper workflows that can be used to simplify other workflows.
Examples include workflows for finding changes in Terraform or running Terraform plan.

### Build, Test and Lint
Workflows prefixed with build, test and lint are meant to simplify the process of building and testing code.

### Package
Workflows prefixed with package are meant to simplify the process of packaging code.
Packaging workflows depend on build and test workflows, so they should be run after those workflows.

Packaging in pull requests need to use `actions/checkout` with the PR head commit sha.
This way, the correct tag will exist for the deploy stage.

### Deploy
Workflows prefixed with deploy are meant to simplify the process of deploying code.

There is an own workflow for deploying to "Test" in branches.
It will need to use `actions/checkout` with the PR head commit sha, so that the correct code is deployed.

# Note on Pull Requests
In pull requests, the default Git sha being used is a temporary merge commit sha (e.g. in for `actions/checkout`).
In workflows meant to be run in pull requests, we want to use the head commit sha of the pull request instead.
Examples include, building in node for static files, deployments of branches and running Terraform plan.
