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
- `gradle-operations` (default `check publish -Dorg.gradle.caching=true --no-daemon`).
  `-Pversion=<version>` is always appended.
- `tag-prefix` (default `v`) and `initial-version` (default `0.0.0`)
- `create-github-release` (default `true`). Set to `false` to only push the tag.
- `jacoco-report-path` (default empty, no coverage). See [Coverage (opt-in)](#coverage-opt-in).

Outputs: `version` and `is-release` (`'true'` or `'false'`).

### Coverage (opt-in)

JaCoCo coverage is off by default. To opt in, apply the `jacoco` plugin in `build.gradle.kts` and enable
the XML report, which Gradle doesn't generate by default:

```kotlin
plugins {
    jacoco
}

tasks.jacocoTestReport {
    dependsOn(tasks.test)
    reports {
        xml.required = true
    }
}
```

Then override both inputs:

```yaml
    with:
      gradle-operations: "check jacocoTestReport publish -Dorg.gradle.caching=true --no-daemon"
      jacoco-report-path: "build/reports/jacoco/test/jacocoTestReport.xml"
```

The coverage table is then added to the job summary and the XML report to the artifact.

## Versioning

The latest tag matching `<tag-prefix>X.Y.Z` is the latest release. If there is none, `initial-version` is
used and a warning is shown.

Add at most one release label to the pull request. More than one fails the run. All other labels are
ignored, including other `release:`-prefixed labels such as `release:notes`.

| Label           | Next version (from `2.3.0`) |
|-----------------|-----------------------------|
| `release:major` | `3.0.0`                     |
| `release:minor` | `2.4.0`                     |
| `release:patch` | `2.3.1`                     |
| no label        | `2.3.1` (snapshot only)     |

| Event | Published version | Result |
|---|---|---|
| `pull_request` | `<next>-PR<number>-SNAPSHOT` | Snapshot (one per PR, PRs don't overwrite each other) |
| `push` to default branch, no release labels since the latest release | `<X.Y.Z+1>-SNAPSHOT` | Snapshot |
| `push` to default branch, at least one release label since the latest release | `<next>` | Release, tag `<prefix><next>` and GitHub Release |
| Any other event or branch | `<next>-SNAPSHOT` | Snapshot |

### Release labels since the latest release

On push, the workflow looks at **every** PR merged since the latest release tag
(`git rev-list --first-parent <latest-tag>..<sha>`), not only the PR of the pushed commit. The largest
requested bump wins. This way a release label is never lost, even if runs finish out of order or a
pending run is replaced by a newer one:

- PR #1 (`release:major`) and PR #2 (`release:patch`) are merged quickly after each other, and #2's run
  finishes first: it releases `3.0.0` (major), containing both PRs. #1's run then finds its commit already
  included in `v3.0.0` and publishes a snapshot.
- A PR with a release label is merged, but its run fails or is replaced: the next push, even without a
  label, releases it.

A commit that is already included in the latest release is never released again (e.g. when re-running a
release run). At most 100 commits since the latest release are checked.

The "On merge" line in a PR's job summary only considers that PR's own label.

### Finding the merged PR

For each commit, the merged PR is found as follows. Squash, merge-commit and rebase merges are all
supported:

1. `gh api repos/{repo}/commits/{sha}/pulls`. For the pushed commit, this is tried up to 3 times, because
   GitHub can link the commit to the PR slightly after the push.
2. The PR whose merge commit is exactly the pushed commit is preferred.
3. Fallback: the PR number in the commit message (`... (#123)` or `Merge pull request #123 ...`),
   only if GitHub confirms that PR was merged as that exact commit.

Commits without a PR are skipped. If a commit message mentions a PR that can't be confirmed, a warning
says its release label was not applied.

## Releases

- The run fails before publishing if the release tag already exists.
- The tag and GitHub Release (with generated notes) are created directly after `publish` succeeds,
  before the report steps, so a report failure can't leave a published release without a tag.
- Runs on the default branch run one at a time and are never cancelled while running. A pending run can be
  replaced by a newer one, but its release label is picked up by the newer run
  (see [Release labels since the latest release](#release-labels-since-the-latest-release)).
- PR runs cancel older runs for the same PR.

## Reports

The job summary shows the latest release, the label, the published version and, on PRs, what merging
will do. It also shows test counts with failed tests (from JUnit XML) and, if
[coverage is enabled](#coverage-opt-in), a JaCoCo coverage table. The summary is written even when the
build fails. The HTML test report (and the JaCoCo XML, if enabled) is uploaded as an artifact.

## Common errors

| Message | Fix |
|---|---|
| `Only one release label is allowed` | Remove all but one `release:*` label from the PR |
| `Tag vX.Y.Z already exists` | The version was already released. Check the tags, or remove a wrong tag |
| `No tag matching 'vX.Y.Z' found` (warning) | Tag the latest existing release, see the [setup guide](../guides/library-releases.md) |
| `Commit ... is already included in release vX.Y.Z` (notice) | The commit was already released, e.g. on a re-run. Nothing to do |
| `PR #N has several release labels ... Using the largest` (warning) | An earlier PR had more than one release label. The largest was used |
| `Commit message refers to PR #N, but no merged pull request could be confirmed` (warning) | The release label was not applied. Release manually or merge a new PR with the label |

## Skipping bot pull requests

Every PR publishes a `-PR<number>-SNAPSHOT`, including PRs from bots such as Renovate. To skip those,
add a condition to the calling job. A skipped job counts as successful for required status checks, so note
that the library's tests then don't run for those PRs either.

```yaml
jobs:
  publish:
    if: github.event_name != 'pull_request' || github.event.pull_request.user.login != 'renovate[bot]'
    uses: nsbno/platform-actions/.github/workflows/publish-library.gradle.yml@v2
```

The push after merging still runs, so a merged Renovate PR publishes a snapshot (or a release, if labelled).

## Related

- [`tools/library-version`](../actions/tools/library-version.md): the action that computes the version.
