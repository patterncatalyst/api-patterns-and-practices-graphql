#!/usr/bin/env bash
# Breaking-change gate: diff contracts/schema/**/*.graphql at HEAD (working tree)
# against the same files on a base git ref (default origin/main).
# When the base ref has no schema yet (first introduction) the gate skips.
# A base ref that does not resolve (not fetched, typo) is an error, not a skip.
#
#   BASE_REF=origin/main   git ref to compare against
#   BASE_DIR=<dir>         compare against a directory of .graphql files instead
#                          of a git ref (used to test the gate itself)
#   NEW_DIR=<dir>          the new side: a directory of .graphql files
#                          (default: schema, the working tree)
#   BREAKING_RULES=<list>  comma-separated graphql-inspector rule names, each
#                          passed as a repeated --rule (default: none). For
#                          example dangerousBreaking fails on dangerous changes
#                          too (strict mode), and suppressRemovalOfDeprecatedField
#                          downgrades the removal of a deprecated field.
#
# Policy: the default gate fails only on breaking changes. Dangerous changes
# (an added enum value, an added optional argument) pass; when GITHUB_ACTIONS=true
# every dangerous line is also echoed as a ::warning annotation so it shows on
# the PR without failing it.
#
# Exit codes: 0 ok or skipped, 1 breaking change (or a dangerous one under
# dangerousBreaking), 2 base ref does not resolve.
set -euo pipefail

cd "$(dirname "$0")/.."            # contracts/
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
BASE_REF="${BASE_REF:-origin/main}"
SCHEMA_PATH="contracts/schema"
inspector=(npx --no-install graphql-inspector)

NEW_DIR="${NEW_DIR:-schema}"
rule_args=()
if [ -n "${BREAKING_RULES:-}" ]; then
  IFS=',' read -r -a _rules <<<"$BREAKING_RULES"
  for r in "${_rules[@]}"; do
    if [ -n "$r" ]; then rule_args+=(--rule "$r"); fi
  done
fi

tmp=""
cleanup() { if [ -n "$tmp" ]; then rm -rf "$tmp"; fi; }
trap cleanup EXIT

if [ -n "${BASE_DIR:-}" ]; then
  base="$BASE_DIR"
else
  if ! git -C "$REPO_ROOT" rev-parse --verify --quiet "${BASE_REF}^{commit}" >/dev/null; then
    echo "base ref '$BASE_REF' does not resolve; fetch it first (git fetch origin main)" >&2
    exit 2
  fi
  # Capture the listing first: piping into `grep -q` under pipefail can SIGPIPE
  # the producer and turn a match into a false "no baseline" skip.
  listing="$(git -C "$REPO_ROOT" ls-tree -r --name-only "$BASE_REF" -- "$SCHEMA_PATH")"
  if ! grep -q '\.graphql$' <<<"$listing"; then
    echo "no baseline schema on $BASE_REF yet - skipping breaking check (first introduction)"
    exit 0
  fi
  tmp="$(mktemp -d)"
  git -C "$REPO_ROOT" archive "$BASE_REF" "$SCHEMA_PATH" | tar -x -C "$tmp"
  base="$tmp/$SCHEMA_PATH"
fi

echo "comparing ${NEW_DIR}/**/*.graphql against ${BASE_DIR:-$BASE_REF}${BREAKING_RULES:+ (rules: $BREAKING_RULES)}"
# Rules go last: --rule is an array option and would swallow the positionals.
# diff exits non-zero on breaking changes (and on dangerous ones only under the
# dangerousBreaking rule); dangerous/non-breaking changes otherwise pass.
rc=0
out="$("${inspector[@]}" diff "$base/**/*.graphql" "$NEW_DIR/**/*.graphql" "${rule_args[@]}" 2>&1)" || rc=$?
printf '%s\n' "$out"

if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
  # A dangerous change is marked with the warning sign in the inspector's log lines.
  while IFS= read -r line; do
    msg="$(sed -E 's/^[[:space:]]*(\[log\])?[[:space:]]*//' <<<"$line")"
    echo "::warning title=Dangerous schema change::${msg}"
  done < <(grep '⚠' <<<"$out" || true)
fi
exit "$rc"
