# Vy Platform Actions — Copilot Instructions

This repository is the **shared GitHub Actions library for Vy**. Workflows and composite actions here are consumed by dozens of other Vy repositories pinned to a `@v2` floating tag. A breaking change in this repo can break CI/CD pipelines across the entire organisation.

## Before reviewing any PR

1. **Read `README.md`** in the repository root. It explains:
   - The floating `@v2` tag strategy and why backward compatibility is non-negotiable
   - The v1→v2 upgrade guide and the types of changes that constituted breaking changes
   - The PR SHA convention (head commit SHA vs. merge commit SHA)

2. **If the PR touches `.github/workflows/` or `.github/actions/`**, read
   `.opencode/skills/validate-github-actions/references/workflow.md` in full before
   writing any review comments. It is the canonical step-by-step validation guide for
   this project and covers syntax rules, input compatibility, expression validation, and
   how to find internal callers.

## Repository structure

| Path | Contents |
|---|---|
| `.github/workflows/` | 30 reusable workflows (`workflow_call`) consumed by other repos |
| `.github/actions/` | 20+ composite actions called from workflows |
| `.opencode/skills/` | AI agent skill definitions and reference documents |

## Key architectural patterns

- **SSM Parameter Store as service registry.** Deployment metadata (ECS cluster/service,
  ECR image base, S3 bucket, CloudFront domain) lives under
  `/__deployment__/<repo>/<dir>/`. Actions read from SSM at deploy time; values must
  never be hardcoded in workflow or action files.

- **Four named GitHub Environments.** Every repo uses `Service`, `Test`, `Stage`, and
  `Production`. Terraform directory autodiscovery (`helpers/terraform-directory-autodiscovery`)
  determines which are active for a given repo.

- **Version handler registration.** Every deploy must call `helpers/register-version` to
  post the git SHA and compute target to the internal tracking API.

- **Comment-driven workflows.** Branch deploys (`.deploy test`/`.deploy stage`), preview
  deployments (`.preview`), and Terraform plan runs (`.tf plan`) are all triggered by PR
  comments via `github/branch-deploy@v11`.

- **Preview environment flavours.** SSR apps → App Runner or ECS Express (URL mapped via
  DynamoDB). SPAs → S3 prefix `pr-<N>/` with CloudFront.

- **PR SHA handling.** In any workflow triggered by a pull request event, the head commit
  SHA (`github.event.pull_request.head.sha`) must be used for `actions/checkout` and
  packaging steps. Using `github.sha` in a PR context gives the temporary merge commit,
  which is wrong.

## Naming conventions

| Category | Pattern | Example |
|---|---|---|
| Build | `build.<language>.yml` | `build.node.yml` |
| Test | `test.<language>.yml` | `test.python.yml` |
| Lint | `lint.<tool>.yml` | `lint.terraform.yml` |
| Package | `package.<target>.yml` | `package.docker.yml` |
| Deploy | `deployment.<scope>.yml` | `deployment.single-environment.yml` |
| Deploy (preview) | `deployment.preview*.yml` | `deployment.preview-spa.yml` |
| Deploy (comment) | `deployment.*.on-comment.yml` | `deployment.preview.on-comment.yml` |
| Helpers | `helpers.<category>.yml` | `helpers.find-changes.terraform.yml` |

Composite actions use directory-based naming: `.github/actions/<category>/<name>/action.yml`.

## Review priorities for this project

When evaluating a PR, focus on:

1. **Backward compatibility** — new required inputs without defaults are breaking changes
   that affect all `@v2` consumers.
2. **Correctness of input definitions and passing** — extra inputs to a reusable workflow
   are a hard runtime error; missing required inputs silently produce wrong values.
3. **Security** — only raise a finding when you can describe a concrete exploit path.
   Do not report theoretical risks or pre-existing patterns. Authoritative reference:
   [GitHub Actions security hardening](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions).
4. **No hardcoded infrastructure values** — cluster names, bucket names, and domains must
   come from inputs or SSM.
5. **Reuse of existing building blocks** — steps already provided by `helpers/` or
   `tools/` composite actions should not be duplicated in workflow files.
6. **Correct PR SHA usage** — workflows triggered by pull requests must use the head
   commit SHA, not the merge commit SHA.
