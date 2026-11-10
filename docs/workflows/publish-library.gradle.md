# Publish Gradle library

**Workflow:** [`.github/workflows/publish-library.gradle.yml`](../../.github/workflows/publish-library.gradle.yml)

Builds, tests and publishes an internal JVM library to Nexus with Gradle's `maven-publish`.
Releases happen automatically when a pull request with a release label is merged to the default branch.

The workflow never pushes commits. The version comes from git tags and is passed to Gradle as
`-Pversion=<version>`, which overrides `version` in `gradle.properties`. This works with a protected
default branch and no bot with bypass rights.

First time using it in a repository? Follow the setup guide: [Library releases](../guides/library-releases.md).

## Example

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
    uses: nsbno/platform-actions/.github/workflows/publish-library.gradle.yml@v2
    with:
      java-version: "17"
    secrets: inherit
```

The `labeled` and `unlabeled` triggers make the PR run update when release labels change.

## Permissions and secrets

| Permission | Why |
|---|---|
| `contents: write` | Create release tags and GitHub Releases |
| `pull-requests: read` | Read the labels of the merged PR on push |

| Secret | Required |
|---|---|
| `NEXUS_USERNAME`, `NEXUS_PASSWORD` | Yes (org-level secrets, passed with `secrets: inherit`) |
| `BUILD_CACHE_USERNAME`, `BUILD_CACHE_PASSWORD`, `GRADLE_CACHE_ENCRYPTION_KEY` | No |

## Inputs

All inputs are optional. See the [workflow file](../../.github/workflows/publish-library.gradle.yml)
for the full list with descriptions and defaults. The most common ones:

- `java-version` (default `"21"`) and `java-distribution` (default `temurin`)
- `working-directory` (default `.`)
- `gradle-operations` (default `check jacocoTestReport publish -Dorg.gradle.caching=true --no-daemon`).
  `-Pversion=<version>` is always appended.
- `tag-prefix` (default `v`) and `initial-version` (default `0.0.0`)
- `create-github-release` (default `true`). Set to `false` to only push the tag.
- `jacoco-report-path`. Set to empty to skip the coverage summary.

Outputs: `version` and `is-release` (`'true'` or `'false'`).

## Versioning

The latest tag matching `<tag-prefix>X.Y.Z` is the latest release. If there is none, `initial-version` is
used and a warning is shown.

Add at most one release label to the pull request. More than one fails the run. Other labels are ignored.

| Label           | Next version (from `2.3.0`) |
|-----------------|-----------------------------|
| `release:major` | `3.0.0`                     |
| `release:minor` | `2.4.0`                     |
| `release:patch` | `2.3.1`                     |
| no label        | `2.3.1` (snapshot only)     |

| Event | Published version | Result |
|---|---|---|
| `pull_request` | `<next>-PR<number>-SNAPSHOT` | Snapshot (one per PR, PRs don't overwrite each other) |
| `push` to default branch, merged PR without release label (or no PR found) | `<X.Y.Z+1>-SNAPSHOT` | Snapshot |
| `push` to default branch, merged PR with release label | `<next>` | Release, tag `<prefix><next>` and GitHub Release |
| Any other event or branch | `<next>-SNAPSHOT` | Snapshot |

### Finding the merged PR

On push, the merged PR is found from the pushed commit. Squash, merge-commit and rebase merges are all
supported:

1. `gh api repos/{repo}/commits/{sha}/pulls` is tried up to 3 times, because GitHub can link the commit
   to the PR slightly after the push.
2. The PR whose merge commit is exactly the pushed commit is preferred.
3. Fallback: the PR number in the commit message (`... (#123)` or `Merge pull request #123 ...`),
   only if GitHub confirms that PR was merged as that exact commit.

If no PR is found, a snapshot is published. If the commit message mentions a PR that can't be
confirmed, a warning says the release label was not applied.

## Releases

- The run fails before publishing if the release tag already exists.
- The tag and GitHub Release (with generated notes) are created only after `publish` succeeds.
- Releases on the default branch are never cancelled by newer runs, so they happen one at a time.
  PR runs cancel older runs for the same PR.

## Reports

The job summary shows the latest release, the label, the published version and, on PRs, what merging
will do. It also shows test counts with failed tests (from JUnit XML) and a JaCoCo coverage table.
The summary is written even when the build fails. The HTML test report and the JaCoCo XML are
uploaded as an artifact.

## Common errors

| Message | Fix |
|---|---|
| `Only one release label is allowed` | Remove all but one `release:*` label from the PR |
| `Tag vX.Y.Z already exists` | The version was already released. Check the tags, or remove a wrong tag |
| `No tag matching 'vX.Y.Z' found` (warning) | Tag the latest existing release, see the [setup guide](../guides/library-releases.md) |
| `Commit message refers to PR #N, but no merged pull request could be confirmed` (warning) | The release label was not applied. Release manually or merge a new PR with the label |

## Related

- [`tools/library-version`](../actions/tools/library-version.md): the action that computes the version.
