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
  * [Publish](#publish)
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

### Publish
Workflows prefixed with publish build, test and publish libraries.

#### Gradle library (`publish.gradle-library.yml`)
Builds, tests and publishes an internal JVM library to Nexus with Gradle's `maven-publish`.
Releases happen automatically when a pull request with a release label is merged to the default branch.
The workflow never pushes commits; the version comes from git tags and is passed to Gradle as
`-Pversion=<version>`, which overrides `version` in `gradle.properties`.

The latest tag matching `<tag-prefix>X.Y.Z` (default `v`) is the latest release. If there is none,
`initial-version` (default `0.0.0`) is used and a warning is shown.
Add at most one release label to the pull request (more than one fails the run, other labels are ignored):

| Label           | Next version (from `2.3.0`) |
|-----------------|-----------------------------|
| `release:major` | `3.0.0`                     |
| `release:minor` | `2.4.0`                     |
| `release:patch` | `2.3.1`                     |
| no label        | `2.3.1` (snapshot only)     |

| Event                                                          | Published version         | Result                                  |
|----------------------------------------------------------------|---------------------------|-----------------------------------------|
| `pull_request`                                                 | `<next>-PR<number>-SNAPSHOT` | Snapshot (one per PR)                |
| `push` to default branch, merged PR without release label      | `<X.Y.Z+1>-SNAPSHOT`      | Snapshot                                |
| `push` to default branch, merged PR with release label         | `<next>`                  | Release, tag `<prefix><next>` and GitHub Release |
| Any other event or branch                                      | `<next>-SNAPSHOT`         | Snapshot                                |

On push, the merged PR is found from the pushed commit. Squash, merge-commit and rebase merges are all supported:
the lookup is retried briefly (GitHub can link the commit to the PR slightly after the push), prefers the PR
whose merge commit is exactly the pushed commit, and falls back to the PR number in the commit message
(`... (#123)` or `Merge pull request #123 ...`) if GitHub confirms that PR was merged as that commit.
If no PR can be found, a snapshot is published. Releases fail before publishing if
the tag already exists, and the tag/GitHub Release is only created after a successful publish.
Set `create-github-release: false` to only push the tag. Test results and JaCoCo coverage are written to the
job summary, and the reports are uploaded as an artifact.

The version logic is also available as a standalone composite action,
`nsbno/platform-actions/.github/actions/tools/library-version@v2`, for other library types.

```yaml
name: Build and publish
on:
  pull_request:
    types: [opened, synchronize, reopened, labeled, unlabeled]
  push:
    branches: [main]
permissions:
  contents: write       # create tags and GitHub Releases
  pull-requests: read   # read labels of the merged PR
jobs:
  publish:
    uses: nsbno/platform-actions/.github/workflows/publish.gradle-library.yml@v2
    with:
      java-version: "17"
    secrets: inherit
```

**One-time setup per repository:**
1. Create the labels:
   ```shell
   gh label create release:major --color B60205 --description "Release a new major version on merge"
   gh label create release:minor --color FBCA04 --description "Release a new minor version on merge"
   gh label create release:patch --color 0E8A16 --description "Release a new patch version on merge"
   ```
2. If there are no `vX.Y.Z` tags yet, tag the latest existing release, e.g.
   `git tag v2.3.0 <sha> && git push origin v2.3.0`.
3. Make sure `build.gradle.kts` selects the repository from the version suffix, e.g.
   `if (version.toString().endsWith("SNAPSHOT")) "maven-snapshots-v2" else "maven-releases"`,
   and reads credentials from `NEXUS_USERNAME`/`NEXUS_PASSWORD`.
4. Set `version=0.0.0-LOCAL-SNAPSHOT` in `gradle.properties` for local builds.

### Deploy
Workflows prefixed with deploy are meant to simplify the process of deploying code.

The branch deployment workflow supports deployments to Development, Test, and Stage using
the `.deploy dev`, `.deploy test`, and `.deploy stage` PR comments.
It uses the PR head commit SHA so that the correct code is deployed.

# Note on Pull Requests
In pull requests, the default Git sha being used is a temporary merge commit sha (e.g. in for `actions/checkout`).
In workflows meant to be run in pull requests, we want to use the head commit sha of the pull request instead.
Examples include, building in node for static files, deployments of branches and running Terraform plan.
