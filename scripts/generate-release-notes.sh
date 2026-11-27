#!/usr/bin/env bash
# Generates grouped release notes from Conventional Commits.
# Usage: scripts/generate-release-notes.sh <tag>
set -euo pipefail

TAG="${1:?usage: generate-release-notes.sh <tag>}"
REPOSITORY="${GITHUB_REPOSITORY:-mentalfl0w/BlueLink}"

if git rev-parse -q --verify "refs/tags/${TAG}^{commit}" >/dev/null; then
  END="$TAG"
else
  END="HEAD"
fi

PREVIOUS="$(git describe --tags --abbrev=0 "${END}^" 2>/dev/null || true)"
if [[ -n "$PREVIOUS" ]]; then
  RANGE="${PREVIOUS}..${END}"
  COMPARE_URL="https://github.com/${REPOSITORY}/compare/${PREVIOUS}...${TAG}"
else
  RANGE="$END"
  COMPARE_URL="https://github.com/${REPOSITORY}/commits/${TAG}"
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/bluelink-release-notes.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
for section in feat fix perf refactor docs build ci test chore other; do
  : > "$TMP/$section"
done

pattern='^([a-z]+)(\([^)]*\))?!?:[[:space:]]+(.+)$'
while IFS=$'\t' read -r sha subject; do
  [[ -z "$sha" ]] && continue
  short="${sha:0:7}"
  entry="- ${subject} ([${short}](https://github.com/${REPOSITORY}/commit/${sha}))"
  if [[ "$subject" =~ $pattern ]]; then
    type="${BASH_REMATCH[1]}"
    case "$type" in
      feat|fix|perf|refactor|docs|build|ci|test|chore)
        printf '%s\n' "$entry" >> "$TMP/$type"
        ;;
      *)
        printf '%s\n' "$entry" >> "$TMP/other"
        ;;
    esac
  else
    printf '%s\n' "$entry" >> "$TMP/other"
  fi
done < <(git log --no-merges --reverse --pretty=format:'%H%x09%s%n' "$RANGE")

printf "## What's Changed\n\n"
first=true
for section in feat fix perf refactor docs build ci test chore other; do
  if [[ -s "$TMP/$section" ]]; then
    if [[ "$first" == false ]]; then printf '\n'; fi
    case "$section" in
      feat) heading="Features" ;;
      fix) heading="Fixes" ;;
      perf) heading="Performance" ;;
      refactor) heading="Refactoring" ;;
      docs) heading="Documentation" ;;
      build) heading="Build" ;;
      ci) heading="CI" ;;
      test) heading="Tests" ;;
      chore) heading="Chores" ;;
      other) heading="Other Changes" ;;
    esac
    printf '### %s\n\n' "$heading"
    cat "$TMP/$section"
    first=false
  fi
done

printf '\n**Full Changelog**: %s\n' "$COMPARE_URL"
printf '\n---\n\n'
printf 'This is an ad-hoc signed build. It is not Developer ID signed or notarized. '
printf 'Real Bluetooth sleep/wake behavior has not been validated on hardware; '
printf 'see [VERIFICATION.md](https://github.com/%s/blob/%s/docs/VERIFICATION.md).\n' "$REPOSITORY" "$TAG"
