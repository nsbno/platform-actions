#!/usr/bin/env bash
# Computes the library version from git tags and pull request release labels.
#
# Expected environment:
#   TAG_PREFIX, INITIAL_VERSION, EVENT_NAME, REF, DEFAULT_BRANCH, SHA, REPOSITORY,
#   PR_NUMBER, PR_LABELS (JSON array of label names, pull_request events only), GH_TOKEN
# Writes outputs to $GITHUB_OUTPUT (or stdout when unset) and a summary to $GITHUB_STEP_SUMMARY.
set -euo pipefail

TAG_PREFIX="${TAG_PREFIX-v}"
INITIAL_VERSION="${INITIAL_VERSION:-0.0.0}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/stdout}"
GITHUB_STEP_SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

if ! [[ "$INITIAL_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "::error::initial-version '$INITIAL_VERSION' is not of the form X.Y.Z"
  exit 1
fi

# Latest release tag matching <prefix>X.Y.Z
latest_tag=""
while IFS= read -r tag; do
  if [[ "${tag#"$TAG_PREFIX"}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$tag" == "$TAG_PREFIX"* ]]; then
    latest_tag="$tag"
    break
  fi
done < <(git tag --list "${TAG_PREFIX}*" --sort=-v:refname)

if [[ -n "$latest_tag" ]]; then
  previous_version="${latest_tag#"$TAG_PREFIX"}"
else
  previous_version="$INITIAL_VERSION"
  echo "::warning::No tag matching '${TAG_PREFIX}X.Y.Z' found. Falling back to initial-version ${INITIAL_VERSION}."
fi

RELEASE_LABELS_FILTER='.[] | select(. == "release:major" or . == "release:minor" or . == "release:patch")'

bump_rank() {
  case "$1" in major) echo 3 ;; minor) echo 2 ;; patch) echo 1 ;; *) echo 0 ;; esac
}

# Prints the merged PR (JSON) for a commit on the default branch, or nothing.
# Squash, merge and rebase merges all link the commit to the PR, but the link can appear slightly
# after the push event, so the lookup is retried. The PR whose merge commit is this exact commit is
# preferred. Fallback: the PR number in the commit message ("... (#123)" or "Merge pull request #123"),
# only trusted if GitHub confirms that PR was merged as this exact commit.
find_merged_pr() {
  local commit="$1" attempts="$2" attempt pulls merged="" message message_pr candidate
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    pulls="$(gh api "repos/${REPOSITORY}/commits/${commit}/pulls")"
    merged="$(jq -c --arg sha "$commit" '
      [.[] | select(.merged_at != null)] as $m
      | ([$m[] | select(.merge_commit_sha == $sha)][0] // $m[0]) // empty' <<<"$pulls")"
    [[ -n "$merged" ]] && break
    if (( attempt < attempts )); then
      echo "No merged pull request linked to ${commit} yet (attempt ${attempt}/${attempts}), retrying..." >&2
      sleep "${PR_LOOKUP_DELAY:-5}"
    fi
  done

  message="$(git log -1 --format=%B "$commit" 2>/dev/null || true)"
  message_pr="$(sed -nE '1{s/^Merge pull request #([0-9]+) .*/\1/p;s/.*\(#([0-9]+)\)[[:space:]]*$/\1/p}' <<<"$message" | head -n1)"
  if [[ -z "$merged" && -n "$message_pr" ]]; then
    echo "Looking up PR #${message_pr} from the commit message of ${commit}" >&2
    candidate="$(gh api "repos/${REPOSITORY}/pulls/${message_pr}" 2>/dev/null || true)"
    merged="$(jq -c --arg sha "$commit" 'select(.merged_at != null and .merge_commit_sha == $sha)' <<<"${candidate:-null}" 2>/dev/null || true)"
    if [[ -z "$merged" ]]; then
      echo "::warning::Commit message of ${commit} refers to PR #${message_pr}, but no merged pull request could be confirmed. Its release label (if any) was NOT applied." >&2
    fi
  fi
  printf '%s' "$merged"
}

bump="none"
release_labels=()
requests=()
is_default_push="false"
if [[ "$EVENT_NAME" == "pull_request" || "$EVENT_NAME" == "pull_request_target" ]]; then
  labels_json="${PR_LABELS:-[]}"
  [[ "$labels_json" == "null" ]] && labels_json="[]"
  mapfile -t release_labels < <(jq -r "$RELEASE_LABELS_FILTER" <<<"$labels_json")
  if (( ${#release_labels[@]} > 1 )); then
    echo "::error::Only one release label is allowed, found: ${release_labels[*]}"
    exit 1
  fi
  (( ${#release_labels[@]} == 1 )) && bump="${release_labels[0]#release:}"

elif [[ "$EVENT_NAME" == "push" && "$REF" == "refs/heads/${DEFAULT_BRANCH}" ]]; then
  is_default_push="true"

  if [[ -n "$latest_tag" ]] && git merge-base --is-ancestor "$SHA" "$latest_tag" 2>/dev/null; then
    # Re-run of a release, or an older run that finished after a newer release. That release
    # already accounted for every release label up to it (see below), so there is nothing to release.
    echo "::notice::Commit ${SHA} is already included in release ${latest_tag}. Publishing a snapshot."
    already_released="$latest_tag"
  else
    # Every merged PR since the latest release counts, not only the one for the pushed commit.
    # Runs can finish out of order or be replaced while pending, so a release label is applied by
    # whichever run releases first, and the largest requested bump wins.
    if [[ -n "$latest_tag" ]]; then
      mapfile -t commits < <(git rev-list --first-parent "${latest_tag}..${SHA}")
    else
      commits=("$SHA")
    fi
    max_commits="${PR_LOOKUP_MAX_COMMITS:-100}"
    if (( ${#commits[@]} > max_commits )); then
      echo "::warning::${#commits[@]} commits since ${latest_tag}. Only the latest ${max_commits} are checked for release labels."
      commits=("${commits[@]:0:max_commits}")
    fi

    seen=" "
    for commit in "${commits[@]}"; do
      attempts=1
      [[ "$commit" == "$SHA" ]] && attempts="${PR_LOOKUP_ATTEMPTS:-3}"
      merged="$(find_merged_pr "$commit" "$attempts")"
      if [[ -z "$merged" ]]; then
        [[ "$commit" == "$SHA" ]] && echo "::notice::No merged pull request found for ${SHA}."
        continue
      fi
      number="$(jq -r '.number' <<<"$merged")"
      [[ "$seen" == *" ${number} "* ]] && continue
      seen+="${number} "
      [[ "$commit" == "$SHA" ]] && PR_NUMBER="$number"

      mapfile -t pr_labels < <(jq -r "[.labels[].name] | ${RELEASE_LABELS_FILTER}" <<<"$merged")
      (( ${#pr_labels[@]} == 0 )) && continue
      if (( ${#pr_labels[@]} > 1 )); then
        if [[ "$commit" == "$SHA" ]]; then
          echo "::error::Only one release label is allowed, found on PR #${number}: ${pr_labels[*]}"
          exit 1
        fi
        echo "::warning::PR #${number} has several release labels (${pr_labels[*]}). Using the largest."
      fi
      for label in "${pr_labels[@]}"; do
        pr_bump="${label#release:}"
        (( $(bump_rank "$pr_bump") > $(bump_rank "$bump") )) && bump="$pr_bump"
        release_labels+=("$label")
      done
      requests+=("#${number} \`${pr_labels[*]}\`")
      echo "PR #${number} (${commit}) requests: ${pr_labels[*]}"
    done
    if (( ${#requests[@]} == 0 )); then
      echo "No unreleased release labels since ${latest_tag:-the beginning}. Publishing a snapshot."
    fi
  fi
fi

IFS=. read -r major minor patch <<<"$previous_version"
case "$bump" in
  major) next="$((major + 1)).0.0" ;;
  minor) next="${major}.$((minor + 1)).0" ;;
  *) next="${major}.${minor}.$((patch + 1))" ;;
esac

is_release="false"
tag=""
if [[ "$EVENT_NAME" == "pull_request" || "$EVENT_NAME" == "pull_request_target" ]]; then
  version="${next}-PR${PR_NUMBER}-SNAPSHOT"
  if [[ "$bump" == "none" ]]; then
    on_merge="snapshot only — add a \`release:*\` label to release"
  else
    on_merge="release **${next}**"
  fi
elif [[ "$is_default_push" == "true" && "$bump" != "none" ]]; then
  version="$next"
  is_release="true"
  tag="${TAG_PREFIX}${next}"
else
  version="${next}-SNAPSHOT"
fi

{
  echo "version=${version}"
  echo "is-release=${is_release}"
  echo "tag=${tag}"
  echo "bump=${bump}"
  echo "previous-version=${previous_version}"
} >>"$GITHUB_OUTPUT"

{
  echo "### Library version"
  echo ""
  echo "| | |"
  echo "|---|---|"
  echo "| Latest release | $([[ -n "$latest_tag" ]] && echo "\`${previous_version}\` (tag \`${latest_tag}\`)" || echo "none (using \`${INITIAL_VERSION}\`)") |"
  if [[ "$is_default_push" == "true" ]]; then
    requests_text="none"
    if (( ${#requests[@]} )); then
      requests_text="$(printf '%s, ' "${requests[@]}")"
      requests_text="${requests_text%, }"
    fi
    echo "| Release requests since latest release | ${requests_text} |"
  else
    echo "| Release label | $([[ ${#release_labels[@]} -eq 1 ]] && echo "\`${release_labels[0]}\`" || echo none) |"
  fi
  echo "| Version | \`${version}\` |"
  echo "| Type | $([[ "$is_release" == "true" ]] && echo "release (tag \`${tag}\`)" || echo snapshot) |"
  if [[ -n "${already_released:-}" ]]; then
    echo "| Note | Commit is already included in \`${already_released}\`, nothing to release |"
  fi
  if [[ -n "${on_merge:-}" ]]; then
    echo "| On merge | ${on_merge} |"
  fi
  echo ""
} >>"$GITHUB_STEP_SUMMARY"

echo "Version: ${version} (release: ${is_release}, bump: ${bump}, previous: ${previous_version})"
