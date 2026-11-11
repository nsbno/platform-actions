# Publish Gradle library

**Workflow:** [`.github/workflows/publish-library.gradle.yml`](../../.github/workflows/publish-library.gradle.yml)

Publishes an internal JVM library to Nexus with Gradle's `maven-publish`. Releases happen automatically
when a pull request with a release label is merged to the default branch.

This workflow only publishes. Building and testing are done by
[`test.gradle.yml`](../../.github/workflows/test.gradle.yml), which the caller runs first and chains with
`needs:`, so nothing is published if the tests fail.

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
  test:
    uses: nsbno/platform-actions/.github/workflows/test.gradle.yml@v2
    with:
      java-version: "17"
    secrets: inherit

  publish:
    needs: test
    uses: nsbno/platform-actions/.github/workflows/publish-library.gradle.yml@v2
    with:
      java-version: "17"
    secrets: inherit
```

- The `labeled` and `unlabeled` triggers make the PR run update when release labels change.
- The publish job runs Gradle again, but with the build cache it reuses the compiled classes. `publish`
  doesn't depend on the test task, so tests don't run twice.
- Inputs like `java-version` and `working-directory` must be set the same way on both jobs.

## Permissions and secrets

The workflow limits its job to the permissions below, but a reusable workflow can't grant itself more
than the caller allows. Declare them in the caller (as in the example), or GitHub rejects the run at
startup with a message naming the missing permission.

| Permission | Why |
|---|---|
| `contents: write` | Create release tags and GitHub Releases |
| `pull-requests: read` | Read the labels of merged PRs on push |

| Secret | Required |
|---|---|
| `NEXUS_USERNAME`, `NEXUS_PASSWORD` | Yes (org-level secrets, passed with `secrets: inherit`) |
| `BUILD_CACHE_USERNAME`, `BUILD_CACHE_PASSWORD`, `GRADLE_CACHE_ENCRYPTION_KEY` | No |

## Inputs

All inputs are optional. See the [workflow file](../../.github/workflows/publish-library.gradle.yml)
for the full list with descriptions and defaults. The most common ones:

- `java-version` (default `"21"`) and `java-distribution` (default `temurin`)
- `working-directory` (default `.`)
- `gradle-operations` (default `publish -Dorg.gradle.caching=true --no-daemon`).
  `-Pversion=<version>` is always appended.
- `tag-prefix` (default `v`) and `initial-version` (default `0.0.0`)
- `create-github-release` (default `true`). Set to `false` to only push the tag.

Outputs: `version` and `is-release` (`'true'` or `'false'`).

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
release run). If there is no release tag yet, the whole first-parent history is checked. In both cases, at
most the latest 100 commits are checked.

If a GitHub API lookup fails for any of these commits, the run stops before publishing, so a release
request is never skipped because of an API error. Re-run the workflow to try again.

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
- The tag and GitHub Release (with generated notes) are created directly after `publish` succeeds.
- Runs on the default branch run one at a time and are never cancelled while running. A pending run can be
  replaced by a newer one, but its release label is picked up by the newer run
  (see [Release labels since the latest release](#release-labels-since-the-latest-release)).
- PR runs cancel older runs for the same PR.

## Job summary

The job summary shows the latest release, the release labels, the published version and, on PRs, what
merging will do. Test reports come from the test job (see `upload-test-report` in
[`test.gradle.yml`](../../.github/workflows/test.gradle.yml)).

## Common errors

| Message | Fix |
|---|---|
| `Only one release label is allowed` | Remove all but one `release:*` label from the PR |
| `Tag vX.Y.Z already exists` | The version was already released. Check the tags, or remove a wrong tag |
| `No tag matching 'vX.Y.Z' found` (warning) | Tag the latest existing release, see the [setup guide](../guides/library-releases.md) |
| `Commit ... is already included in release vX.Y.Z` (notice) | The commit was already released, e.g. on a re-run. Nothing to do |
| `Could not determine the pull request for <sha>` | A GitHub API lookup failed. Nothing was published. Re-run the workflow |
| `PR #N has several release labels ... Using the largest` (warning) | An earlier PR had more than one release label. The largest was used |
| `Commit message refers to PR #N, but no merged pull request could be confirmed` (warning) | The release label was not applied. Release manually or merge a new PR with the label |

## Skipping bot pull requests

Every PR publishes a `-PR<number>-SNAPSHOT`, including PRs from bots such as Renovate. To skip those,
add a condition to the publish job. The test job still runs, and a skipped job counts as successful for
required status checks.

```yaml
jobs:
  publish:
    needs: test
    if: github.event_name != 'pull_request' || github.event.pull_request.user.login != 'renovate[bot]'
    uses: nsbno/platform-actions/.github/workflows/publish-library.gradle.yml@v2
```

The push after merging still runs, so a merged Renovate PR publishes a snapshot (or a release, if labelled).

## Related

- [`tools/library-version`](../actions/tools/library-version.md): the action that computes the version.
