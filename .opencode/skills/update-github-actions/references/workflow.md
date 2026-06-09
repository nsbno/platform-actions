# Update GitHub Actions Workflow

## Pinning rules

The pin method depends on the action owner. Apply these rules consistently:

| Action category | Pin method | Example |
|---|---|---|
| `actions/checkout` | Floating major version tag | `actions/checkout@v4` |
| `actions/upload-artifact` | Floating major version tag | `actions/upload-artifact@v7` |
| `actions/download-artifact` | Floating major version tag | `actions/download-artifact@v8` |
| `actions/setup-java` | Full commit SHA + version comment | `actions/setup-java@be666c2f... # v5.2.0` |
| `actions/setup-python` | Full commit SHA + version comment | `actions/setup-python@a309ff8b... # v6.2.0` |
| `github/*` | Full commit SHA + version comment | `github/branch-deploy@ddf8ca48... # v11.1.4` |
| `aws-actions/*` | Floating major version tag | `aws-actions/configure-aws-credentials@v4` |
| `docker/*` | Floating major version tag | `docker/build-push-action@v6` |
| `nsbno/platform-actions/*` | **Skip** — internal, not updated here | — |
| All other third-party | Full commit SHA + version comment | `astral-sh/setup-uv@abc123def... # v8.1.0` |

> `github/*`, `actions/setup-java`, and `actions/setup-python` are SHA-pinned (not floating) because they touch sensitive runtime environments or deployment logic and an unreviewed tag move would be high-impact.

**Why SHA pinning?** A floating tag like `@v8` can be silently redirected to a different commit by the action owner (intentionally or after a supply-chain compromise). SHA pinning freezes the exact code that runs. The human-readable version comment preserves discoverability.

**Version comment format:** Add the version as an inline comment immediately after the SHA:
```yaml
uses: astral-sh/setup-uv@08807647e7069bb48b6ef5acd8ec9567f424441b # v8.1.0
```

---

## 1. Discover all external actions

Read every `.github/workflows/*.yml` file (and any `.github/actions/**/action.yml` that calls external actions). Extract every `uses:` line. Collect the unique set of external actions, skipping:
- `./` paths (local composite actions)
- `nsbno/platform-actions/*` (internal — owned by this repo)

Build a table:

| Action | Current pin | Pin type |
|---|---|---|
| `actions/checkout` | `@v6` | Floating |
| `astral-sh/setup-uv` | `@08807647...` | SHA (v8.1.0) |
| … | … | … |

If the same action is pinned inconsistently across files (e.g., `@v6` in one, `@a309ff8b...` in another), note the inconsistency — it should be resolved to a single version.

---

## 2. Fetch the latest release for each action

Use `gh release view` or the GitHub API. Always fetch from the official source.

### Check if a newer version exists

```bash
# Latest release tag and body
gh release view --repo {owner}/{repo} --json tagName,name,publishedAt,body

# List recent releases (useful to see the full version history)
gh release list --repo {owner}/{repo} --limit 10 --json tagName,publishedAt,isLatest,isPreRelease
```

Filter out pre-releases and drafts unless the current pin is also a pre-release.

### Determine the update type

Compare the current version to the latest:

| Update type | Example | Caution level |
|---|---|---|
| **Patch** | `v8.1.0` → `v8.1.1` | Low — apply by default |
| **Minor** | `v8.0.0` → `v8.1.0` | Medium — check release notes |
| **Major** | `v8.x.x` → `v9.0.0` | High — read §5 carefully before updating |

For actions using floating major tags (`actions/*`, `aws-actions/*`, `docker/*`), a new major version means changing `@v8` to `@v9`. Treat this the same as a major update. For `github/*` (SHA-pinned), fetch the new commit SHA and update accordingly.

---

## 3. Get the commit SHA for a release tag (SHA-pinned actions only)

The GitHub tags API always returns the actual commit SHA (it dereferences annotated tags automatically):

```bash
OWNER="astral-sh"
REPO="setup-uv"
TAG="v8.1.0"

SHA=$(gh api "repos/$OWNER/$REPO/tags" --paginate \
  --jq ".[] | select(.name == \"$TAG\") | .commit.sha")

echo "$SHA"
```

If the `--paginate` call is slow (repo has many tags), use the git refs API and dereference manually:

```bash
REF=$(gh api "repos/$OWNER/$REPO/git/refs/tags/$TAG")
OBJ_TYPE=$(echo "$REF" | jq -r '.object.type')
OBJ_SHA=$(echo "$REF" | jq -r '.object.sha')

if [ "$OBJ_TYPE" = "tag" ]; then
  # Annotated tag — dereference to get the actual commit SHA
  SHA=$(gh api "repos/$OWNER/$REPO/git/tags/$OBJ_SHA" | jq -r '.object.sha')
else
  # Lightweight tag — already a commit SHA
  SHA="$OBJ_SHA"
fi

echo "$TAG @ $SHA"
```

Verify the SHA is 40 characters long. A short SHA is a sign something went wrong.

---

## 4. Check for known vulnerabilities

Check the OSV database (no auth required) for each action:

```bash
OWNER="astral-sh"
REPO="setup-uv"

curl -s "https://api.osv.dev/v1/query" \
  -H "Content-Type: application/json" \
  -d "{\"package\": {\"name\": \"$OWNER/$REPO\", \"ecosystem\": \"GitHub Actions\"}}" \
  | jq '.vulns // [] | length'
```

If any vulnerabilities are returned:

```bash
curl -s "https://api.osv.dev/v1/query" \
  -H "Content-Type: application/json" \
  -d "{\"package\": {\"name\": \"$OWNER/$REPO\", \"ecosystem\": \"GitHub Actions\"}}" \
  | jq '.vulns[] | {id, summary, affected: .affected[].ranges}'
```

**Decision rules:**
- Vulnerability affects the current version **and** is fixed in the target version → update immediately, flag in the summary.
- Vulnerability affects the target version too → **do not update**, flag as blocked, report to the user.
- No vulnerabilities → proceed.

Also check if the action repository has been archived, renamed, or transferred — these are risk signals. Visit `https://github.com/{owner}/{repo}` or run:

```bash
gh api "repos/$OWNER/$REPO" --jq '{archived: .archived, disabled: .disabled, visibility: .visibility}'
```

---

## 5. Review release notes for breaking changes

Always read the release notes before updating. Focus on what can impact this repository.

```bash
# Show full body of the latest release
gh release view --repo {owner}/{repo} --json tagName,body --jq '.body'

# For a range of releases (e.g., going from v8.0.0 to v8.2.0)
gh release list --repo {owner}/{repo} --limit 20 --json tagName,publishedAt \
  | jq '.[] | .tagName'
# Then fetch each release body between the two versions
```

### Patch and minor updates

Look for:
- Deprecated inputs/outputs that we currently use
- Changed default values for inputs we rely on
- Environment or runner version requirements that changed

If the release notes are clean and there are no deprecations affecting our usage → update.

### Major version updates

A major version bump is a **breaking change boundary**. Before updating, check the full migration guide. Look for:

1. **Removed or renamed inputs** — check every `with:` block in our workflows that uses this action. If we pass an input that was removed, the workflow will fail.
2. **Changed output names** — check every `${{ steps.<id>.outputs.<name> }}` reference after this action.
3. **Changed environment requirements** — e.g., minimum runner OS, Node.js version bundled, new required permissions.
4. **Changed behavior for existing inputs** — a default value change can silently alter pipeline behavior.
5. **Removed runner support** — e.g., dropping `ubuntu-20.04` support.

For a major update, list every workflow file and specific `with:` argument we use for this action, then cross-reference against the breaking changes list. Only proceed if none of our usages are affected, or if you can update all affected call sites in the same change.

If the impact is unclear, **skip the major update** and note it in the summary with a link to the migration guide.

---

## 6. Apply the updates

### Updating floating-version actions (`actions/*`, `aws-actions/*`, `docker/*`)

Replace only the version suffix. Preserve the rest of the line exactly.

```yaml
# Before
- uses: actions/checkout@v5

# After (major bump)
- uses: actions/checkout@v6
```

### Updating SHA-pinned actions

Replace the full `@{sha}` and the version comment. The SHA must be the full 40-character commit hash.

```yaml
# Before
- uses: astral-sh/setup-uv@08807647e7069bb48b6ef5acd8ec9567f424441b # v8.1.0

# After
- uses: astral-sh/setup-uv@a39d71779d1b28ac4e2e5c2cc02f53124ac0f82b # v8.2.0
```

If an action is currently pinned with a floating tag but should be SHA-pinned (per the pinning rules above), convert it in the same change:

```yaml
# Before (incorrect — community third-party should be SHA-pinned)
- uses: mikefarah/yq@v4.40.5

# After (correct)
- uses: mikefarah/yq@a2a52a81514b56b3816abd4c08ac8ca18a1d7e5d # v4.44.3
```

### Resolving inconsistent pins

If the same action is pinned differently across multiple files (e.g., `@v6` in one and `@a309ff8b...` in another), unify all occurrences to the latest correct pin in the same PR.

---

## 7. Verification

After making changes, run the validate-github-actions skill (if available) to check that all workflow files remain syntactically valid and that no callers are broken.

At minimum, verify manually:
- No `uses:` line was partially updated (e.g., SHA without comment, or mixed old/new versions)
- The SHA is 40 characters for all SHA-pinned actions
- All occurrences of each action across all workflow files are updated, not just the first one

---

## 8. Summary report

After completing the updates, produce a concise summary:

```
## GitHub Actions Update Summary

### Updated
| Action | Old | New | Type |
|---|---|---|---|
| `astral-sh/setup-uv` | `v8.1.0` | `v8.2.0` | Patch |
| `actions/checkout` | `@v5` | `@v6` | Major |

### Skipped (breaking changes or vulnerabilities in target)
| Action | Current | Latest | Reason |
|---|---|---|---|
| `docker/build-push-action` | `@v6` | `@v7` | Major — input `provenance` changed default; review required |

### Already up to date
- `hashicorp/setup-terraform` (v4.0)
- `github/branch-deploy` (v11)
```

If no updates were needed, say so clearly.

---

## Quick reference: all external actions in this repo

| Action | Should be pinned? | Official releases page |
|---|---|---|
| `actions/checkout` | Floating (`@vN`) | https://github.com/actions/checkout/releases |
| `actions/upload-artifact` | Floating (`@vN`) | https://github.com/actions/upload-artifact/releases |
| `actions/download-artifact` | Floating (`@vN`) | https://github.com/actions/download-artifact/releases |
| `actions/setup-java` | SHA | https://github.com/actions/setup-java/releases |
| `actions/setup-python` | SHA | https://github.com/actions/setup-python/releases |
| `github/branch-deploy` | SHA | https://github.com/github/branch-deploy/releases |
| `aws-actions/configure-aws-credentials` | Floating (`@vN`) | https://github.com/aws-actions/configure-aws-credentials/releases |
| `aws-actions/amazon-ecr-login` | Floating (`@vN`) | https://github.com/aws-actions/amazon-ecr-login/releases |
| `docker/setup-buildx-action` | Floating (`@vN`) | https://github.com/docker/setup-buildx-action/releases |
| `docker/build-push-action` | Floating (`@vN`) | https://github.com/docker/build-push-action/releases |
| `astral-sh/setup-uv` | SHA | https://github.com/astral-sh/setup-uv/releases |
| `hashicorp/setup-terraform` | SHA | https://github.com/hashicorp/setup-terraform/releases |
| `mikefarah/yq` | SHA | https://github.com/mikefarah/yq/releases |
