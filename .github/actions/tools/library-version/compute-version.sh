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

# Labels of the relevant pull request
labels_json="[]"
is_default_push="false"
if [[ "$EVENT_NAME" == "pull_request" || "$EVENT_NAME" == "pull_request_target" ]]; then
  labels_json="${PR_LABELS:-[]}"
  [[ "$labels_json" == "null" ]] && labels_json="[]"
elif [[ "$EVENT_NAME" == "push" && "$REF" == "refs/heads/${DEFAULT_BRANCH}" ]]; then
  is_default_push="true"
  # Squash, merge and rebase merges all link the pushed commit to the PR, but the link can appear
  # slightly after the push event, so retry. Prefer the PR whose merge commit is this exact commit.
  merged=""
  attempts="${PR_LOOKUP_ATTEMPTS:-3}"
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    pulls="$(gh api "repos/${REPOSITORY}/commits/${SHA}/pulls")"
    merged="$(jq -c --arg sha "$SHA" '
      [.[] | select(.merged_at != null)] as $m
      | ([$m[] | select(.merge_commit_sha == $sha)][0] // $m[0]) // empty' <<<"$pulls")"
    [[ -n "$merged" ]] && break
    if (( attempt < attempts )); then
      echo "No merged pull request linked to ${SHA} yet (attempt ${attempt}/${attempts}), retrying..."
      sleep "${PR_LOOKUP_DELAY:-5}"
    fi
  done

  # Fallback: the PR number in the commit message ("... (#123)" for squash merges,
  # "Merge pull request #123 from ..." for merge commits). Only trusted if GitHub confirms
  # that the PR was merged as this exact commit.
  message="$(git log -1 --format=%B "$SHA" 2>/dev/null || true)"
  message_pr="$(sed -nE '1{s/^Merge pull request #([0-9]+) .*/\1/p;s/.*\(#([0-9]+)\)[[:space:]]*$/\1/p}' <<<"$message" | head -n1)"
  if [[ -z "$merged" && -n "$message_pr" ]]; then
    echo "Looking up PR #${message_pr} from the commit message"
    candidate="$(gh api "repos/${REPOSITORY}/pulls/${message_pr}" 2>/dev/null || true)"
    merged="$(jq -c --arg sha "$SHA" 'select(.merged_at != null and .merge_commit_sha == $sha)' <<<"${candidate:-null}" 2>/dev/null || true)"
  fi

  if [[ -n "$merged" ]]; then
    PR_NUMBER="$(jq -r '.number' <<<"$merged")"
    labels_json="$(jq -c '[.labels[].name]' <<<"$merged")"
    echo "Commit ${SHA} belongs to merged PR #${PR_NUMBER}"
  else
    PR_NUMBER=""
    if [[ -n "$message_pr" ]]; then
      echo "::warning::Commit message refers to PR #${message_pr}, but no merged pull request could be confirmed for ${SHA}. Publishing a snapshot; any release label was NOT applied."
    else
      echo "::notice::No merged pull request found for ${SHA}. Publishing a snapshot."
    fi
  fi
fi

mapfile -t release_labels < <(jq -r '.[] | select(startswith("release:"))' <<<"$labels_json")
if (( ${#release_labels[@]} > 1 )); then
  echo "::error::Only one release label is allowed, found: ${release_labels[*]}"
  exit 1
fi

bump="none"
if (( ${#release_labels[@]} == 1 )); then
  case "${release_labels[0]}" in
    release:major) bump="major" ;;
    release:minor) bump="minor" ;;
    release:patch) bump="patch" ;;
    *)
      echo "::error::Unknown release label '${release_labels[0]}'. Use release:major, release:minor or release:patch."
      exit 1
      ;;
  esac
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
  echo "| Latest release | ${latest_tag:-none (using ${INITIAL_VERSION})} |"
  echo "| Release label | ${release_labels[0]:-none} |"
  echo "| Version | \`${version}\` |"
  echo "| Type | $([[ "$is_release" == "true" ]] && echo "release (tag \`${tag}\`)" || echo snapshot) |"
  if [[ -n "${on_merge:-}" ]]; then
    echo "| On merge | ${on_merge} |"
  fi
  echo ""
} >>"$GITHUB_STEP_SUMMARY"

echo "Version: ${version} (release: ${is_release}, bump: ${bump}, previous: ${previous_version})"
