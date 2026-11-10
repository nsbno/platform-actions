# Library version

**Action:** [`.github/actions/tools/library-version/action.yml`](../../../.github/actions/tools/library-version/action.yml)

Computes a library version from the latest `<tag-prefix>X.Y.Z` git tag and the `release:major`,
`release:minor` or `release:patch` label on the pull request. It works on its own, so it can be used by
library workflows for any build tool (Gradle, Maven, npm, ...).

Used by [`publish.gradle-library.yml`](../../workflows/publish.gradle-library.md), which also documents
the versioning rules in full.

## Example

```yaml
steps:
  - uses: actions/checkout@v6
    with:
      fetch-depth: 0   # tags are required
      ref: ${{ github.event.pull_request.head.sha || github.sha }}

  - uses: nsbno/platform-actions/.github/actions/tools/library-version@v2
    id: version

  - run: ./publish.sh "$VERSION"
    env:
      VERSION: ${{ steps.version.outputs.version }}
```

The job needs `pull-requests: read` to look up the merged PR on push.
The action only computes the version. Creating tags and releases is up to the caller.

## Inputs

| Input | Default | Description |
|---|---|---|
| `tag-prefix` | `v` | Prefix of release tags |
| `initial-version` | `0.0.0` | Used as the latest release when no matching tag exists |
| `github-token` | `${{ github.token }}` | Token for looking up the merged PR |

## Outputs

| Output | Example | Description |
|---|---|---|
| `version` | `2.4.0`, `2.4.0-SNAPSHOT`, `2.4.0-PR64-SNAPSHOT` | The computed version |
| `is-release` | `'true'` / `'false'` | Whether this run should publish a release |
| `tag` | `v2.4.0` | Release tag to create. Empty unless releasing |
| `bump` | `major`, `minor`, `patch`, `none` | The requested bump |
| `previous-version` | `2.3.0` | The latest release, or `initial-version` |

The action also writes a version table to the job summary.

## Testing locally

The logic is in [`compute-version.sh`](../../../.github/actions/tools/library-version/compute-version.sh)
and reads everything from environment variables. Run it in a git repo with tags:

```shell
EVENT_NAME=pull_request PR_NUMBER=64 PR_LABELS='["release:minor"]' \
  bash .github/actions/tools/library-version/compute-version.sh
```

For push events, set `EVENT_NAME=push`, `REF=refs/heads/main`, `DEFAULT_BRANCH=main`, `SHA`,
`REPOSITORY`, and put a fake `gh` on the `PATH` that returns the API responses.
`PR_LOOKUP_DELAY=0` skips the wait between retries.
