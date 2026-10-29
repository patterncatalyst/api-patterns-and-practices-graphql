#!/usr/bin/env bash
# examples/_lib/lib.sh
#
# Shared verification harness for every hands-on example's verify.sh.
# Source this file, then use the functions below to bring up the example's
# docker compose stack, wait for the GraphQL endpoint, send operations with
# curl, and assert RESPONSE SEMANTICS against the canonical SDL — not just an
# HTTP 200. A 200 that carries a wrong-shaped or wrong-valued result must fail
# the check (GraphQL-over-HTTP returns 200 for application/json responses
# even when the body holds `errors`, so the status alone proves nothing).
#
# Usage (from an example's verify.sh):
#
#   #!/usr/bin/env bash
#   set -euo pipefail
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   # shellcheck source=SCRIPTDIR/../_lib/lib.sh
#   source "$SCRIPT_DIR/../_lib/lib.sh"
#
#   PROJECT="gql-ch00-prereq"             # unique per example, for CI isolation
#   compose_up "$SCRIPT_DIR/compose.yaml" "$PROJECT"
#
#   wait_for_graphql http://localhost:8080/graphql
#   resp="$(gql http://localhost:8080/graphql \
#            'query($t: TrackingId!) { cargo(trackingId: $t) { description } }' \
#            '{"t":"ABC123"}')"
#   assert_no_errors "$resp"
#   assert_eq "Palletized electronics" "$(json_field '.data.cargo.description' <<<"$resp")" "description"
#   assert_sdl_conforms http://localhost:8080/graphql
#
# compose_down runs automatically on EXIT via a trap registered by compose_up.
# To clean up anything else (a scratch directory, a background process), register
# it with `on_exit <command...>`: the hooks run after the stack is torn down, in
# registration order, and the script keeps its exit status. Never set your own
# EXIT trap in a verify.sh that sources this file; it would replace this one.
#
# This file is bash-only (BASH_SOURCE, [[ ]], arrays, process substitution).
# Never source it from zsh or sh.
#
# This file must stay `bash -n` clean: scripts/validate.py runs `bash -n` on
# every *.sh in the repo.

set -euo pipefail

# ---------------------------------------------------------------------------
# Path resolution — works regardless of the calling example's cwd.
# ---------------------------------------------------------------------------

LGTM_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$LGTM_LIB_DIR/../.." && pwd)"
export REPO_ROOT

CONTRACTS_DIR="$REPO_ROOT/contracts"
# Quoted when passed to graphql-inspector so the tool expands the glob itself.
CANONICAL_SDL_GLOB="$CONTRACTS_DIR/schema/**/*.graphql"

# ---------------------------------------------------------------------------
# Self-contained contract tooling: graphql-inspector is pinned in
# contracts/package.json and installed with `npm ci`, so verify.sh needs no
# pre-installed tool beyond Node/npm (CI sets Node up with actions/setup-node).
# ---------------------------------------------------------------------------

# The install runs under an exclusive flock so that verify.sh runs started
# concurrently (the CI matrix, or several chapters on one host) never race an
# `npm ci`, which removes and recreates node_modules. The check is repeated
# once the lock is held: a run that waited finds the tools installed by the one
# that went first. Never delete or reinstall contracts/node_modules by hand
# while verify.sh runs are in flight.
ensure_contracts_tools() {
  if ! command -v npm >/dev/null 2>&1; then
    echo "lib.sh: FAIL — npm is required to install graphql-inspector (contracts/package.json)" >&2
    return 1
  fi
  local lock="${TMPDIR:-/tmp}/gql-contracts-npm.lock"
  (
    if command -v flock >/dev/null 2>&1; then
      flock 9
    fi
    if [[ -x "$CONTRACTS_DIR/node_modules/.bin/graphql-inspector" ]]; then
      exit 0
    fi
    echo "lib.sh: installing pinned contract tooling (npm ci --prefix contracts) ..." >&2
    npm ci --prefix "$CONTRACTS_DIR" --no-audit --no-fund >&2
  ) 9>"$lock"
}

# ---------------------------------------------------------------------------
# Docker compose lifecycle
# ---------------------------------------------------------------------------

_LIB_COMPOSE_FILE=""
_LIB_COMPOSE_PROJECT=""

# compose_up <compose-file> <project-name>
compose_up() {
  local compose_file="$1"
  local project="$2"

  if [[ ! -f "$compose_file" ]]; then
    echo "lib.sh: compose file not found: $compose_file" >&2
    return 1
  fi
  if ! command -v docker >/dev/null 2>&1; then
    echo "lib.sh: docker is required but not found on PATH" >&2
    return 1
  fi
  if ! docker compose version >/dev/null 2>&1; then
    echo "lib.sh: 'docker compose' (v2 plugin) is required; legacy docker-compose is not supported" >&2
    return 1
  fi

  _LIB_COMPOSE_FILE="$compose_file"
  _LIB_COMPOSE_PROJECT="$project"

  # Start from a clean project: a stack left running by a reader's own session
  # (for example after the chapter's "On the wire" commands) holds state that
  # would make the assertions of a mutating example fail.
  docker compose -p "$project" -f "$compose_file" down -v --remove-orphans >/dev/null 2>&1 || true

  echo "lib.sh: docker compose -p $project up -d --build" >&2
  docker compose -p "$project" -f "$compose_file" up -d --build

  trap '_lib_exit_trap $?' EXIT
}

# on_exit <command...> — register a command to run when the script exits, after
# _lib_teardown. Hooks run in registration order; a failing hook does not stop
# the others or change the exit status. The words are joined and evaluated, so
# quote the whole command: on_exit 'rm -rf "$scratch"'. Works with or without
# compose_up.
_LIB_EXIT_HOOKS=()
on_exit() {
  if (( $# == 0 )); then
    echo "lib.sh: FAIL — on_exit needs a command" >&2
    return 1
  fi
  _LIB_EXIT_HOOKS+=("$*")
  trap '_lib_exit_trap $?' EXIT
}

# _lib_exit_trap <exit-status> — the one EXIT trap: _lib_teardown (only when a
# stack is up), then every on_exit hook in order; exits with the original status.
_lib_exit_trap() {
  local rc="$1" hook
  local -a hooks=("${_LIB_EXIT_HOOKS[@]}")
  _LIB_EXIT_HOOKS=()
  trap - EXIT
  set +e
  if [[ -n "$_LIB_COMPOSE_PROJECT" ]]; then
    _lib_teardown "$rc"
  fi
  for hook in "${hooks[@]}"; do
    eval "$hook" || echo "lib.sh: on_exit hook failed (ignored): $hook" >&2
  done
  exit "$rc"
}

# _lib_teardown <exit-status> — the EXIT trap: on a failed run, print the
# per-container exit state (restart count, OOM kill, exit code, applied memory
# and CPU limits) and the tail of every service's log before the stack (and its
# logs) goes away. The exit state tells apart a clean failed assertion from a
# container the runner's kernel killed and compose then revived with fresh state.
_lib_teardown() {
  local rc="$1" cid
  if (( rc != 0 )) && [[ -n "$_LIB_COMPOSE_PROJECT" ]]; then
    echo "lib.sh: run failed (exit $rc); container exit state:" >&2
    for cid in $(docker compose -p "$_LIB_COMPOSE_PROJECT" -f "$_LIB_COMPOSE_FILE" ps -aq 2>/dev/null); do
      docker inspect -f '  {{.Name}} status={{.State.Status}} OOMKilled={{.State.OOMKilled}} exit={{.State.ExitCode}} restarts={{.RestartCount}} startedAt={{.State.StartedAt}} finishedAt={{.State.FinishedAt}} memLimit={{.HostConfig.Memory}} nanoCpus={{.HostConfig.NanoCpus}} error={{.State.Error}}' "$cid" >&2 || true
    done
    echo "lib.sh: last 200 log lines per service:" >&2
    docker compose -p "$_LIB_COMPOSE_PROJECT" -f "$_LIB_COMPOSE_FILE" logs --no-color --tail 200 >&2 || true
  fi
  compose_down "$_LIB_COMPOSE_FILE" "$_LIB_COMPOSE_PROJECT"
}

# compose_logs <service> — print one service's logs of the running stack
# (docker compose logs --no-color). Fails when no stack was started.
compose_logs() {
  if [[ -z "$_LIB_COMPOSE_PROJECT" ]]; then
    echo "lib.sh: FAIL — compose_logs: no stack is up (call compose_up first)" >&2
    return 1
  fi
  docker compose -p "$_LIB_COMPOSE_PROJECT" -f "$_LIB_COMPOSE_FILE" logs --no-color "$1"
}

# compose_run <service> [args...] — run one service of the running stack as a
# one-off container: docker compose run --rm -T --build <service> args... .
# Services behind a compose profile (a client, a composer) run through it, so
# compose_up stays the same for every example. Fails when no stack was started.
compose_run() {
  if [[ -z "$_LIB_COMPOSE_PROJECT" ]]; then
    echo "lib.sh: FAIL — compose_run: no stack is up (call compose_up first)" >&2
    return 1
  fi
  if (( $# == 0 )); then
    echo "lib.sh: FAIL — compose_run needs a service name" >&2
    return 1
  fi
  # COMPOSE_PROGRESS=quiet keeps BuildKit progress out of stdout, so the
  # service's own output is all a caller captures.
  COMPOSE_PROGRESS=quiet docker compose -p "$_LIB_COMPOSE_PROJECT" -f "$_LIB_COMPOSE_FILE" run --rm -T --build "$@"
}

# compose_down <compose-file> <project-name>
compose_down() {
  local compose_file="$1"
  local project="$2"

  if [[ -z "$project" ]]; then
    return 0
  fi

  echo "lib.sh: docker compose -p $project down -v --remove-orphans" >&2
  docker compose -p "$project" -f "$compose_file" down -v --remove-orphans || true
}

# session_start — install the harness EXIT trap for a script that never calls
# compose_up (a cluster smoke.sh): the on_exit hooks then run when the script
# exits. Safe to call more than once, and a later compose_up keeps the same
# single trap.
session_start() {
  trap '_lib_exit_trap $?' EXIT
}

# compose_inspect <service> <go-template> — docker inspect -f <template> on the
# service's container of the running stack, found through docker compose ps -q.
# Fails when the stack is not up or the service has no container.
compose_inspect() {
  local service="${1:-}" template="${2:-}" cid
  if [[ -z "$_LIB_COMPOSE_PROJECT" ]]; then
    echo "lib.sh: FAIL — compose_inspect: no stack is up (call compose_up first)" >&2
    return 1
  fi
  if [[ -z "$service" || -z "$template" ]]; then
    echo "lib.sh: FAIL — compose_inspect needs a service and a Go template" >&2
    return 1
  fi
  cid="$(docker compose -p "$_LIB_COMPOSE_PROJECT" -f "$_LIB_COMPOSE_FILE" ps -q "$service")" || return 1
  if [[ -z "$cid" ]]; then
    echo "lib.sh: FAIL — compose_inspect: service '$service' has no container" >&2
    return 1
  fi
  docker inspect -f "$template" "$cid"
}

# compose_exec_http <service> <method> <path> [curl-args...] — one request made
# from inside the service's container, to http://localhost:8080<path>: it
# reaches endpoints the edge does not route. Output as http_any: the status on
# line 1, then the body. Non-zero only when the exec or the transport fails.
compose_exec_http() {
  local service="${1:-}" method="${2:-}" path="${3:-}" out status body
  if [[ -z "$_LIB_COMPOSE_PROJECT" ]]; then
    echo "lib.sh: FAIL — compose_exec_http: no stack is up (call compose_up first)" >&2
    return 1
  fi
  if [[ -z "$service" || -z "$method" || -z "$path" ]]; then
    echo "lib.sh: FAIL — compose_exec_http needs a service, a method and a path" >&2
    return 1
  fi
  shift 3
  # The status code follows the body on its own line; splitting at the last
  # newline gives http_any's layout (status first) for any body.
  out="$(docker compose -p "$_LIB_COMPOSE_PROJECT" -f "$_LIB_COMPOSE_FILE" exec -T "$service" \
    curl -sS --max-time "${LGTM_HTTP_TIMEOUT:-30}" -X "$method" -w $'\n%{http_code}' "$@" \
    "http://localhost:8080$path")" || return 1
  status="${out##*$'\n'}"
  body="${out%$'\n'*}"
  printf '%s\n%s\n' "$status" "$body"
}

# run_load <service> <run> <expected-iterations> [-e K=V ...] — one load run of
# a compose service (k6): compose_run with RUN=<run> and the extra -e pairs,
# then read the k6 summary JSON from the last line of stdout. Passes when
# metrics.iterations.values.count equals the expectation and
# metrics.checks.values.rate is 1. Prints the summary line, which a caller can
# keep for further fields. A run that exits non-zero (a failed threshold) fails
# with the tail of its output.
run_load() {
  local service="${1:-}" run="${2:-}" expected="${3:-}" out err summary count rate
  if [[ -z "$service" || -z "$run" || -z "$expected" ]]; then
    echo "lib.sh: FAIL — run_load needs a service, a run name and the expected iteration count" >&2
    return 1
  fi
  shift 3
  err="$(mktemp)"
  if ! out="$(compose_run -e "RUN=$run" "$@" "$service" 2>"$err")"; then
    echo "lib.sh: FAIL — run_load: '$run' on $service exited non-zero:" >&2
    tail -30 "$err" >&2
    printf '%s\n' "$out" | tail -5 >&2
    rm -f "$err"
    return 1
  fi
  rm -f "$err"
  summary="$(printf '%s\n' "$out" | tail -n 1)"
  count="$(json_field '.metrics.iterations.values.count' <<<"$summary")" || {
    echo "lib.sh: FAIL — run_load: no k6 summary JSON on the last line of '$run'" >&2
    return 1
  }
  rate="$(json_field '.metrics.checks.values.rate' <<<"$summary")" || {
    echo "lib.sh: FAIL — run_load: the summary of '$run' has no checks rate" >&2
    return 1
  }
  assert_eq "$expected" "$count" "run_load $run: iterations" || return 1
  assert_eq "1" "$rate" "run_load $run: every check true" || return 1
  printf '%s\n' "$summary"
}

# ---------------------------------------------------------------------------
# GraphQL helpers (GraphQL-over-HTTP, application/json, POST)
# ---------------------------------------------------------------------------

# _gql_body <query> [variables-json] [operationName] — the JSON request body,
# built with python's json module so quotes and newlines in the query are
# escaped safely. "operationName" is added only when the third argument is
# non-empty.
_gql_body() {
  python3 -I -c '
import json, sys
query = sys.argv[1]
variables = json.loads(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2] else {}
body = {"query": query, "variables": variables}
if len(sys.argv) > 3 and sys.argv[3]:
    body["operationName"] = sys.argv[3]
print(json.dumps(body))
' "$@"
}

# _lib_curl_opts [--no-bearer] [--no-trace] — fills the global array
# _LIB_CURL_OPTS with the extra curl arguments the environment asks for, so every
# curl in this file adds them from one place:
#   LGTM_CACERT       a PEM file: adds --cacert (HTTPS endpoints with a private CA)
#   LGTM_BEARER       a token: adds -H "Authorization: Bearer ..." (Ch18)
#   LGTM_TRACEPARENT  a W3C traceparent value: adds -H "traceparent: ..." so the
#                     request joins a trace the script chose (Ch19)
#   LGTM_HEADERS      newline-separated `Name: value` lines, one -H each; blank
#                     lines are skipped (for example X-Client-Name, Ch19)
# All unset or empty: the array is empty and curl behaves as before. Callers
# expand it as "${_LIB_CURL_OPTS[@]}" right after calling this function.
# --no-bearer leaves the Authorization header out (the token endpoint).
# --no-trace leaves traceparent and LGTM_HEADERS out (the telemetry backends).
_LIB_CURL_OPTS=()
_lib_curl_opts() {
  local arg line no_bearer=0 no_trace=0
  for arg in "$@"; do
    case "$arg" in
      --no-bearer) no_bearer=1 ;;
      --no-trace) no_trace=1 ;;
    esac
  done
  _LIB_CURL_OPTS=()
  if [[ -n "${LGTM_CACERT:-}" ]]; then
    _LIB_CURL_OPTS+=(--cacert "$LGTM_CACERT")
  fi
  if [[ -n "${LGTM_BEARER:-}" ]] && (( no_bearer == 0 )); then
    _LIB_CURL_OPTS+=(-H "Authorization: Bearer $LGTM_BEARER")
  fi
  if (( no_trace == 0 )); then
    if [[ -n "${LGTM_TRACEPARENT:-}" ]]; then
      _LIB_CURL_OPTS+=(-H "traceparent: $LGTM_TRACEPARENT")
    fi
    if [[ -n "${LGTM_HEADERS:-}" ]]; then
      while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -n "${line//[[:space:]]/}" ]] && _LIB_CURL_OPTS+=(-H "$line")
      done <<<"$LGTM_HEADERS"
    fi
  fi
  return 0
}

# wait_for_graphql <url> [timeout_secs]
#
# Polls the endpoint with a trivial `{ __typename }` POST until it answers 200
# with data.__typename == "Query", or fails loudly after timeout_secs (default
# 90, to cover JVM cold start).
wait_for_graphql() {
  local url="$1"
  local timeout="${2:-90}"
  local waited=0
  local interval=3
  local body out

  body="$(_gql_body '{ __typename }')"
  _lib_curl_opts
  echo "lib.sh: waiting for GraphQL $url (timeout ${timeout}s) ..." >&2
  while (( waited < timeout )); do
    if out="$(curl -fsS --max-time 5 "${_LIB_CURL_OPTS[@]}" -H 'Content-Type: application/json' \
          -H 'Accept: application/json' -d "$body" "$url" 2>/dev/null)" \
       && [[ "$(json_field '.data.__typename' <<<"$out" 2>/dev/null || true)" == "Query" ]]; then
      echo "lib.sh: GraphQL $url is up after ${waited}s" >&2
      return 0
    fi
    sleep "$interval"
    waited=$(( waited + interval ))
  done

  echo "lib.sh: FAIL — GraphQL $url did not come up within ${timeout}s" >&2
  return 1
}

# gql <url> <query> [variables-json] [operationName]
#
# POSTs {query, variables[, operationName]} as application/json and prints the
# response body. Fails on any non-200 status. A 200 can still carry a top-level
# `errors` array (GraphQL-over-HTTP, application/json), so callers assert on the
# body: assert_no_errors for success paths, assert_has_errors for failure paths.
gql() {
  local url="$1"
  local query="$2"
  local variables="${3:-}"
  local operation="${4:-}"
  local body tmp status

  body="$(_gql_body "$query" "$variables" "$operation")"
  tmp="$(mktemp)"
  _lib_curl_opts
  status="$(curl -sS --max-time "${LGTM_HTTP_TIMEOUT:-30}" "${_LIB_CURL_OPTS[@]}" -o "$tmp" -w '%{http_code}' -X POST \
    -H 'Content-Type: application/json' -H 'Accept: application/json' \
    -d "$body" "$url")" || { rm -f "$tmp"; return 1; }
  if [[ "$status" != "200" ]]; then
    echo "lib.sh: FAIL — POST $url returned HTTP $status: $(cat "$tmp")" >&2
    rm -f "$tmp"
    return 1
  fi
  cat "$tmp"
  rm -f "$tmp"
}

# gql_any <url> <query> [variables-json] [operationName] [accept]
#
# POSTs like gql but never fails on the HTTP status: line 1 of the output is the
# status code, the rest is the response body. Non-zero only when the transport
# itself fails (connection refused, timeout). Split the output with status_of
# and body_of. Use it where the status is part of what a chapter records. The
# optional fifth argument sets the Accept header (default application/json).
gql_any() {
  local url="$1"
  local query="$2"
  local variables="${3:-}"
  local operation="${4:-}"
  local accept="${5:-application/json}"
  local body tmp status

  body="$(_gql_body "$query" "$variables" "$operation")"
  tmp="$(mktemp)"
  _lib_curl_opts
  status="$(curl -sS --max-time "${LGTM_HTTP_TIMEOUT:-30}" "${_LIB_CURL_OPTS[@]}" -o "$tmp" -w '%{http_code}' -X POST \
    -H 'Content-Type: application/json' -H "Accept: $accept" \
    -d "$body" "$url")" || { rm -f "$tmp"; return 1; }
  printf '%s\n' "$status"
  cat "$tmp"
  rm -f "$tmp"
}

# gql_raw <url> <json-body> [accept] [content-type]
#
# POSTs the body verbatim, with no GraphQL envelope built around it: an APQ
# hash-only request, a batched array, a body sent as text/plain. Output as
# gql_any (line 1 the status, the rest the body); non-zero only when the
# transport fails. Accept defaults to application/json, the content type to
# application/json.
gql_raw() {
  local url="$1"
  local body="$2"
  local accept="${3:-application/json}"
  local ctype="${4:-application/json}"
  local tmp status

  tmp="$(mktemp)"
  _lib_curl_opts
  status="$(curl -sS --max-time "${LGTM_HTTP_TIMEOUT:-30}" "${_LIB_CURL_OPTS[@]}" -o "$tmp" -w '%{http_code}' -X POST \
    -H "Content-Type: $ctype" -H "Accept: $accept" \
    --data-binary "$body" "$url")" || { rm -f "$tmp"; return 1; }
  printf '%s\n' "$status"
  cat "$tmp"
  rm -f "$tmp"
}

# gql_meta <url> <accept> <query> [variables-json]
#
# POSTs with the given Accept header and prints one line, "<status> <media-type>",
# the media type being the response Content-Type without parameters (charset).
# Non-zero only when the transport fails.
gql_meta() {
  local url="$1"
  local accept="$2"
  local query="$3"
  local variables="${4:-}"
  local body line status ctype

  body="$(_gql_body "$query" "$variables")"
  _lib_curl_opts
  line="$(curl -sS --max-time "${LGTM_HTTP_TIMEOUT:-30}" "${_LIB_CURL_OPTS[@]}" -o /dev/null -w '%{http_code} %{content_type}' -X POST \
    -H 'Content-Type: application/json' -H "Accept: $accept" \
    -d "$body" "$url")" || return 1
  status="${line%% *}"
  ctype="${line#* }"
  [[ "$line" == *" "* ]] || ctype=""
  ctype="${ctype%%;*}"
  ctype="${ctype//[[:space:]]/}"
  printf '%s %s\n' "$status" "$ctype"
}

# gql_get <url> <query> [variables-json]
#
# GETs with the query and variables URL-encoded into the query string
# (Accept: application/json). Output format as gql_any. GraphQL-over-HTTP
# allows query operations over GET and requires servers to refuse mutations.
gql_get() {
  local url="$1"
  local query="$2"
  local variables="${3:-}"
  local tmp status
  local -a args=(--data-urlencode "query=$query")

  if [[ -n "$variables" ]]; then
    args+=(--data-urlencode "variables=$variables")
  fi
  tmp="$(mktemp)"
  _lib_curl_opts
  status="$(curl -sS --max-time "${LGTM_HTTP_TIMEOUT:-30}" "${_LIB_CURL_OPTS[@]}" -o "$tmp" -w '%{http_code}' -G \
    -H 'Accept: application/json' "${args[@]}" "$url")" || { rm -f "$tmp"; return 1; }
  printf '%s\n' "$status"
  cat "$tmp"
  rm -f "$tmp"
}

# ---------------------------------------------------------------------------
# Plain HTTP helpers (Ch15 persisted queries, Ch16 caching, Ch17 transport,
# Ch18 authentication). They honour LGTM_CACERT and LGTM_BEARER like gql.
# ---------------------------------------------------------------------------

# http_any <method> <url> [curl-args...]
#
# Any method, any extra curl arguments (for example -H 'Origin: ...'). Line 1 of
# the output is the status code, the rest is the response body. Non-zero only
# when the transport fails (connection refused, TLS verification, timeout).
http_any() {
  local method="$1"
  local url="$2"
  shift 2
  local tmp status
  local -a verb=(-X "$method")

  [[ "$method" == "HEAD" ]] && verb=(--head)
  tmp="$(mktemp)"
  _lib_curl_opts
  status="$(curl -sS --max-time "${LGTM_HTTP_TIMEOUT:-30}" "${_LIB_CURL_OPTS[@]}" "${verb[@]}" \
    -o "$tmp" -w '%{http_code}' "$@" "$url")" || { rm -f "$tmp"; return 1; }
  printf '%s\n' "$status"
  cat "$tmp"
  rm -f "$tmp"
}

# http_headers <method> <url> [curl-args...]
#
# Prints the response headers of the FINAL response as lowercase `name: value`
# lines (the status line is dropped; redirect and 100-continue blocks are
# ignored); the body is discarded. Non-zero only when the transport fails.
http_headers() {
  local method="$1"
  local url="$2"
  shift 2
  local raw
  local -a verb=(-X "$method")

  [[ "$method" == "HEAD" ]] && verb=(--head)
  _lib_curl_opts
  raw="$(curl -sS --max-time "${LGTM_HTTP_TIMEOUT:-30}" "${_LIB_CURL_OPTS[@]}" "${verb[@]}" \
    -D - -o /dev/null "$@" "$url")" || return 1
  python3 -I -c '
import sys
blocks = [b for b in sys.stdin.read().replace("\r\n", "\n").split("\n\n") if b.strip()]
final = [b for b in blocks if b.lstrip().startswith("HTTP/")][-1:]
for line in (final[0].strip().split("\n")[1:] if final else []):
    name, sep, value = line.partition(":")
    if sep:
        print("%s: %s" % (name.strip().lower(), value.strip()))
' <<<"$raw"
}

# header_value <headers> <name> — the value of the (case-insensitive) header in
# an http_headers result, or nothing. A header sent several times prints its
# values joined with ", ".
header_value() {
  python3 -I -c '
import sys
want = sys.argv[1].lower()
vals = []
for line in sys.stdin.read().splitlines():
    name, sep, value = line.partition(":")
    if sep and name.strip().lower() == want:
        vals.append(value.strip())
print(", ".join(vals) if vals else "", end="")
' "$2" <<<"$1"
  echo
}

# assert_header <headers> <name> <expected> [context] — the header is present
# with exactly this value.
assert_header() {
  local headers="$1" name="$2" expected="$3"
  local context="${4:-header $name}"
  local present actual
  present="$(grep -ciE "^${name}:" <<<"$headers" || true)"
  actual="$(header_value "$headers" "$name")"
  if [[ "$present" == "0" ]]; then
    echo "lib.sh: FAIL — ${context}: header '$name' is absent (headers: $(tr '\n' ';' <<<"$headers"))" >&2
    return 1
  fi
  if [[ "$actual" != "$expected" ]]; then
    echo "lib.sh: FAIL — ${context}: header '$name' is '$actual', expected '$expected'" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: $name: $actual" >&2
}

# assert_header_absent <headers> <name> [context] — the header does not occur.
assert_header_absent() {
  local headers="$1" name="$2"
  local context="${3:-no header $name}"
  if grep -qiE "^${name}:" <<<"$headers"; then
    echo "lib.sh: FAIL — ${context}: header '$name' is present: '$(header_value "$headers" "$name")'" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: $name is absent" >&2
}

# assert_transport_fails <context> <curl-args...>
#
# Passes only when curl exits non-zero: TLS verification failure, a protocol
# floor (--tls-max 1.1), a closed port. Any HTTP answer, whatever its status,
# is a FAIL. LGTM_CACERT and LGTM_BEARER are added like everywhere else, so a
# case that must fail for want of the CA runs with `LGTM_CACERT=` (empty).
assert_transport_fails() {
  local context="$1"
  shift
  local rc=0 err
  _lib_curl_opts
  err="$(curl -sS --max-time "${LGTM_HTTP_TIMEOUT:-30}" "${_LIB_CURL_OPTS[@]}" -o /dev/null "$@" 2>&1)" || rc=$?
  if (( rc == 0 )); then
    echo "lib.sh: FAIL — ${context}: curl succeeded, but the transport was expected to fail" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: curl failed as expected (exit $rc: ${err##*curl: })" >&2
}

# wait_for_http <url> [timeout_secs] [expected-status]
#
# Polls a GET until the status equals expected-status (default 200); FAIL after
# timeout_secs (default 90). Honours LGTM_CACERT and LGTM_BEARER, so it also
# waits for HTTPS endpoints and for ones behind a bearer token.
wait_for_http() {
  local url="$1"
  local timeout="${2:-90}"
  local expected="${3:-200}"
  local waited=0
  local interval=2
  local status

  _lib_curl_opts
  echo "lib.sh: waiting for HTTP $expected from $url (timeout ${timeout}s) ..." >&2
  while (( waited < timeout )); do
    status="$(curl -sS --max-time 5 "${_LIB_CURL_OPTS[@]}" -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || true)"
    if [[ "$status" == "$expected" ]]; then
      echo "lib.sh: $url answered $expected after ${waited}s" >&2
      return 0
    fi
    sleep "$interval"
    waited=$(( waited + interval ))
  done

  echo "lib.sh: FAIL — $url did not answer HTTP $expected within ${timeout}s (last status: ${status:-none})" >&2
  return 1
}

# wait_for_json <url> <dot.path> <expected> [timeout_secs]
#
# Polls a GET until the JSON value at the path (json_field syntax) equals the
# expectation, as printed by json_field; FAIL after timeout_secs (default 60).
# Honours LGTM_CACERT and LGTM_BEARER. Use it for a counter a stack publishes,
# such as the subscriber count of a debug endpoint (Ch21).
wait_for_json() {
  local url="$1" path="$2" expected="$3"
  local timeout="${4:-60}"
  local waited=0 interval=1
  local body actual=""

  _lib_curl_opts --no-trace
  echo "lib.sh: waiting for $path == '$expected' at $url (timeout ${timeout}s) ..." >&2
  while (( waited < timeout )); do
    if body="$(curl -fsS --max-time 5 "${_LIB_CURL_OPTS[@]}" -H 'Accept: application/json' "$url" 2>/dev/null)"; then
      actual="$(json_field "$path" <<<"$body" 2>/dev/null || true)"
      if [[ "$actual" == "$expected" ]]; then
        echo "lib.sh: ok — $path is '$actual' at $url after ${waited}s" >&2
        return 0
      fi
    fi
    sleep "$interval"
    waited=$(( waited + interval ))
  done

  echo "lib.sh: FAIL — $path at $url did not become '$expected' within ${timeout}s (last: '${actual:-none}')" >&2
  return 1
}

# sha256_hex <text> — the lowercase hex SHA-256 of the UTF-8 text.
sha256_hex() {
  python3 -I -c '
import hashlib, sys
print(hashlib.sha256(sys.argv[1].encode("utf-8")).hexdigest())
' "$1"
}

# apq_body <query-or-empty> <hash> [variables-json] [operationName]
#
# The Automatic Persisted Queries request body: extensions.persistedQuery
# {version: 1, sha256Hash}. `query` is included only when the first argument is
# non-empty (empty = the hash-only first attempt); `variables` and
# `operationName` only when given. Send it with gql_raw.
apq_body() {
  python3 -I -c '
import json, sys
query, digest = sys.argv[1], sys.argv[2]
body = {}
if query:
    body["query"] = query
if len(sys.argv) > 3 and sys.argv[3]:
    body["variables"] = json.loads(sys.argv[3])
if len(sys.argv) > 4 and sys.argv[4]:
    body["operationName"] = sys.argv[4]
body["extensions"] = {"persistedQuery": {"version": 1, "sha256Hash": digest}}
print(json.dumps(body))
' "$@"
}

# apq_get_url <url> <hash> [variables-json]
#
# The GET form of an APQ request: <url>?variables=...&extensions=..., both
# URL-encoded (compact JSON), for `http_any GET "$(apq_get_url ...)"`. A url
# that already has a query string gets `&` appended instead of `?`.
apq_get_url() {
  python3 -I -c '
import json, sys
from urllib.parse import quote
url, digest = sys.argv[1], sys.argv[2]
parts = []
if len(sys.argv) > 3 and sys.argv[3]:
    parts.append("variables=" + quote(json.dumps(json.loads(sys.argv[3]), separators=(",", ":")), safe=""))
ext = {"persistedQuery": {"version": 1, "sha256Hash": digest}}
parts.append("extensions=" + quote(json.dumps(ext, separators=(",", ":")), safe=""))
print(url + ("&" if "?" in url else "?") + "&".join(parts))
' "$@"
}

# oidc_token <token-url> <client-id> <username> <password>
#
# Resource-owner password grant against an OpenID Connect token endpoint
# (form-encoded POST); prints the access_token. FAILs with the identity
# provider's error text on any other answer.
#
# LAB ONLY. RFC 9700 (OAuth 2.0 Security Best Current Practice) removes the
# password grant: a client must never see the user's password. The workshop uses
# it so a verify.sh can obtain tokens without a browser; a real client uses the
# authorization code flow with PKCE. LGTM_BEARER is not sent to the token
# endpoint; LGTM_CACERT is honoured.
oidc_token() {
  local token_url="$1" client_id="$2" username="$3" password="$4"
  local tmp status token

  tmp="$(mktemp)"
  _lib_curl_opts --no-bearer
  status="$(curl -sS --max-time "${LGTM_HTTP_TIMEOUT:-30}" "${_LIB_CURL_OPTS[@]}" -o "$tmp" -w '%{http_code}' -X POST \
    -H 'Accept: application/json' \
    --data-urlencode 'grant_type=password' \
    --data-urlencode "client_id=$client_id" \
    --data-urlencode "username=$username" \
    --data-urlencode "password=$password" \
    "$token_url")" || { rm -f "$tmp"; return 1; }
  if [[ "$status" != "200" ]]; then
    echo "lib.sh: FAIL — oidc_token: $token_url returned HTTP $status: $(cat "$tmp")" >&2
    rm -f "$tmp"
    return 1
  fi
  token="$(json_field '.access_token' <"$tmp" 2>/dev/null)" || {
    echo "lib.sh: FAIL — oidc_token: no access_token in the answer: $(cat "$tmp")" >&2
    rm -f "$tmp"
    return 1
  }
  rm -f "$tmp"
  printf '%s\n' "$token"
}

# status_of <gql_any-output> — the HTTP status (line 1).
status_of() {
  # Parameter expansion, not a pipe: a pipe into head can close early on a large
  # body and end the writer with SIGPIPE under pipefail.
  printf '%s\n' "${1%%$'\n'*}"
}

# body_of <gql_any-output> — the response body (everything after line 1).
body_of() {
  printf '%s\n' "$1" | tail -n +2
}

# ---------------------------------------------------------------------------
# Assertions (stdlib-python JSON field extraction; no extra deps)
# ---------------------------------------------------------------------------

# json_field <dot.path> — read JSON on stdin, print the value at the given
# dotted path. Supports numeric indices: `.data.cargo.itinerary.legs.0.loadTime`.
# JSON null prints `null`. Prints nothing (and returns non-zero) if the path is
# absent.
json_field() {
  local path="$1"
  python3 -I -c '
import json, sys
path = sys.argv[1].strip(".")
doc = json.load(sys.stdin)
cur = doc
for part in [p for p in path.split(".") if p != ""]:
    if isinstance(cur, list):
        cur = cur[int(part)]
    else:
        cur = cur[part]
if isinstance(cur, (dict, list)):
    print(json.dumps(cur, separators=(",", ":")))
elif isinstance(cur, bool):
    print("true" if cur else "false")
elif cur is None:
    print("null")
else:
    print(cur)
' "$path"
}

# assert_eq <expected> <actual> <context>
assert_eq() {
  local expected="$1"
  local actual="$2"
  local context="${3:-equality}"
  if [[ "$expected" != "$actual" ]]; then
    echo "lib.sh: FAIL — ${context}: expected '$expected', got '$actual'" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: '$actual'" >&2
}

# assert_contains <needle> <haystack> <context>
assert_contains() {
  local needle="$1"
  local haystack="$2"
  local context="${3:-contains}"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "lib.sh: FAIL — ${context}: '$needle' not found" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: found '$needle'" >&2
}

# assert_no_errors <json-response> [context]
#
# Fails if the response has a top-level `errors` key (any value, even []),
# and prints the errors so the failure is diagnosable.
assert_no_errors() {
  local resp="$1"
  local context="${2:-response}"
  local errors
  if errors="$(json_field '.errors' <<<"$resp" 2>/dev/null)"; then
    echo "lib.sh: FAIL — ${context}: top-level errors present: $errors" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: no top-level errors" >&2
}

# assert_has_errors <json-response> [context]
#
# The mirror of assert_no_errors for failure paths: fails unless the response
# carries a non-empty top-level `errors` array.
assert_has_errors() {
  local resp="$1"
  local context="${2:-response}"
  local count
  count="$(python3 -I -c '
import json, sys
errors = json.load(sys.stdin).get("errors")
print(len(errors) if isinstance(errors, list) else 0)
' <<<"$resp")"
  if (( count == 0 )); then
    echo "lib.sh: FAIL — ${context}: expected a non-empty top-level errors array, got: $resp" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: ${count} top-level error(s)" >&2
}

# assert_status_in <"200 400"> <status> [context] — the HTTP status is one of
# the space-separated values.
assert_status_in() {
  local allowed="$1"
  local status="$2"
  local context="${3:-HTTP status}"
  local s
  for s in $allowed; do
    if [[ "$s" == "$status" ]]; then
      echo "lib.sh: ok — ${context}: HTTP $status (allowed: $allowed)" >&2
      return 0
    fi
  done
  echo "lib.sh: FAIL — ${context}: HTTP $status is not one of: $allowed" >&2
  return 1
}

# _json_probe <json> <dot.path> — prints "value:<compact json>" when the path
# resolves, "absent" when its last key is missing from an existing container,
# and "parent-absent" when an earlier step of the path does not resolve (or
# resolves to null), so a mistyped path never reads as a match.
_json_probe() {
  python3 -I -c '
import json, sys
doc = json.load(sys.stdin)
parts = [p for p in sys.argv[1].strip(".").split(".") if p != ""]

def step(cur, part):
    if isinstance(cur, dict):
        return (True, cur[part]) if part in cur else (False, None)
    if isinstance(cur, list):
        try:
            return True, cur[int(part)]
        except (ValueError, IndexError):
            return False, None
    return False, None

cur = doc
for part in parts[:-1]:
    ok, cur = step(cur, part)
    if not ok or cur is None:
        print("parent-absent")
        sys.exit(0)
if parts:
    ok, cur = step(cur, parts[-1])
    if not ok:
        print("absent")
        sys.exit(0)
print("value:" + json.dumps(cur, separators=(",", ":")))
' "$2" <<<"$1"
}

# assert_no_data <json> [context] — `data` is absent or JSON null (a request
# that failed before execution has no data).
assert_no_data() {
  local resp="$1"
  local context="${2:-response}"
  local probe
  probe="$(_json_probe "$resp" '.data')"
  if [[ "$probe" == "absent" || "$probe" == "value:null" ]]; then
    echo "lib.sh: ok — ${context}: no data" >&2
    return 0
  fi
  echo "lib.sh: FAIL — ${context}: expected no data, got: $resp" >&2
  return 1
}

# assert_null_at <json> <dot.path> [context] — the path exists and is JSON null.
# An absent path fails, with a message that says absent.
assert_null_at() {
  local resp="$1"
  local path="$2"
  local context="${3:-$path}"
  local probe
  probe="$(_json_probe "$resp" "$path")"
  case "$probe" in
    value:null)
      echo "lib.sh: ok — ${context}: $path is null" >&2 ;;
    absent|parent-absent)
      echo "lib.sh: FAIL — ${context}: $path is absent (expected an explicit null): $resp" >&2
      return 1 ;;
    *)
      echo "lib.sh: FAIL — ${context}: $path is not null: ${probe#value:}" >&2
      return 1 ;;
  esac
}

# assert_absent <json> <dot.path> [context] — the final key is not present in
# its (existing) parent. A key holding null counts as present and fails.
assert_absent() {
  local resp="$1"
  local path="$2"
  local context="${3:-$path}"
  local probe
  probe="$(_json_probe "$resp" "$path")"
  case "$probe" in
    absent)
      echo "lib.sh: ok — ${context}: $path is absent" >&2 ;;
    parent-absent)
      echo "lib.sh: FAIL — ${context}: the parent of $path is absent or null, so the check proves nothing: $resp" >&2
      return 1 ;;
    *)
      echo "lib.sh: FAIL — ${context}: $path is present: ${probe#value:}" >&2
      return 1 ;;
  esac
}

# assert_error_count <json> <n> [context] — len(errors) == n; absent counts as 0.
assert_error_count() {
  local resp="$1"
  local expected="$2"
  local context="${3:-response}"
  local count
  count="$(python3 -I -c '
import json, sys
errors = json.load(sys.stdin).get("errors")
print(len(errors) if isinstance(errors, list) else 0)
' <<<"$resp")"
  if [[ "$count" != "$expected" ]]; then
    echo "lib.sh: FAIL — ${context}: expected $expected error(s), got $count: $resp" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: $count error(s)" >&2
}

# assert_error_path <json> <path-json-array> [context]
#
# Some errors[i].path equals the array exactly. Types matter: a list index is
# a JSON number, so `0` does not match `"0"`. Prints every path on failure.
assert_error_path() {
  local resp="$1"
  local expected="$2"
  local context="${3:-response}"
  local out
  if out="$(python3 -I -c '
import json, sys
expected = json.loads(sys.argv[1])
errors = json.load(sys.stdin).get("errors") or []
paths = [e.get("path") for e in errors if isinstance(e, dict)]

def same(a, b):
    if type(a) is not type(b):
        return False
    if isinstance(a, list):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    return a == b

if any(same(p, expected) for p in paths):
    sys.exit(0)
print("paths: " + json.dumps(paths, separators=(",", ":")))
sys.exit(1)
' "$expected" <<<"$resp")"; then
    echo "lib.sh: ok — ${context}: error path $expected" >&2
    return 0
  fi
  echo "lib.sh: FAIL — ${context}: no error has path $expected; $out" >&2
  return 1
}

# assert_error_message_contains <json> <needle> [context] — some error message
# contains the needle.
assert_error_message_contains() {
  local resp="$1"
  local needle="$2"
  local context="${3:-response}"
  local messages
  messages="$(python3 -I -c '
import json, sys
for e in json.load(sys.stdin).get("errors") or []:
    print(e.get("message", "") if isinstance(e, dict) else "")
' <<<"$resp")"
  if [[ "$messages" != *"$needle"* ]]; then
    echo "lib.sh: FAIL — ${context}: no error message contains '$needle': $messages" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: an error message contains '$needle'" >&2
}

# _err_check <mode> <json> [args...] — one python entry point for the
# per-error assertions; prints a reason on failure and returns non-zero. An error
# is located by its `path`, compared type-strictly (0 is not "0").
_err_check() {
  local mode="$1"
  local resp="$2"
  shift 2
  python3 -I -c '
import json, sys
mode, args = sys.argv[1], sys.argv[2:]
errors = [e for e in (json.load(sys.stdin).get("errors") or []) if isinstance(e, dict)]

def same(a, b):
    if isinstance(a, bool) or isinstance(b, bool):
        return type(a) is type(b) and a == b
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(same(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    return type(a) is type(b) and a == b

def at(path):
    want = json.loads(path)
    hits = [e for e in errors if same(e.get("path"), want)]
    if not hits:
        print("no error has path %s; paths: %s" % (path, json.dumps([e.get("path") for e in errors], separators=(",", ":"))))
        sys.exit(1)
    return hits[0]

if mode == "message":
    e = at(args[0])
    if e.get("message") != args[1]:
        print("error at %s has message %s, expected %s" % (args[0], json.dumps(e.get("message")), json.dumps(args[1])))
        sys.exit(1)
elif mode == "ext":
    e = at(args[0])
    ext = e.get("extensions")
    if not isinstance(ext, dict) or args[1] not in ext:
        print("error at %s has no extensions.%s (extensions: %s)" % (args[0], args[1], json.dumps(ext)))
        sys.exit(1)
    if not same(ext[args[1]], json.loads(args[2])):
        print("extensions.%s at %s is %s, expected %s" % (args[1], args[0], json.dumps(ext[args[1]]), args[2]))
        sys.exit(1)
elif mode == "ext-absent":
    e = at(args[0])
    ext = e.get("extensions")
    if isinstance(ext, dict) and args[1] in ext:
        print("error at %s has extensions.%s = %s, expected it absent" % (args[0], args[1], json.dumps(ext[args[1]])))
        sys.exit(1)
elif mode == "shape":
    if not errors:
        print("no errors in the response")
        sys.exit(1)
    for i, e in enumerate(errors):
        if not (isinstance(e.get("message"), str) and e["message"]):
            print("errors[%d] has no non-empty message: %s" % (i, json.dumps(e)))
            sys.exit(1)
        if not (isinstance(e.get("locations"), list) and e["locations"]):
            print("errors[%d] has no non-empty locations: %s" % (i, json.dumps(e)))
            sys.exit(1)
        if args[0] == "request" and "path" in e:
            print("request error errors[%d] has a path: %s" % (i, json.dumps(e)))
            sys.exit(1)
        if args[0] == "execution" and not (isinstance(e.get("path"), list) and e["path"]):
            print("execution error errors[%d] has no non-empty path: %s" % (i, json.dumps(e)))
            sys.exit(1)
' "$mode" "$@" <<<"$resp"
}

# assert_error_message_at <json> <path-json-array> <expected> [context] — the
# error whose path equals the array has exactly this message.
assert_error_message_at() {
  local resp="$1" path="$2" expected="$3"
  local context="${4:-error message at $path}"
  local why
  if ! why="$(_err_check message "$resp" "$path" "$expected")"; then
    echo "lib.sh: FAIL — ${context}: $why" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: message at $path is '$expected'" >&2
}

# assert_error_extension <json> <path-json-array> <key> <expected-json> [context]
# — that error's extensions[key] equals the JSON value (types matter: "1" is not 1).
assert_error_extension() {
  local resp="$1" path="$2" key="$3" expected="$4"
  local context="${5:-extensions.$key at $path}"
  local why
  if ! why="$(_err_check ext "$resp" "$path" "$key" "$expected")"; then
    echo "lib.sh: FAIL — ${context}: $why" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: extensions.$key is $expected" >&2
}

# assert_error_extension_absent <json> <path-json-array> <key> [context] — that
# error has no extensions[key]; an error without `extensions` passes.
assert_error_extension_absent() {
  local resp="$1" path="$2" key="$3"
  local context="${4:-no extensions.$key at $path}"
  local why
  if ! why="$(_err_check ext-absent "$resp" "$path" "$key")"; then
    echo "lib.sh: FAIL — ${context}: $why" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: extensions.$key is absent" >&2
}

# assert_error_shape <json> <request|execution> [context] — there is at least
# one error and each has a non-empty message and non-empty locations. request:
# none has a path. execution: each has a non-empty path.
assert_error_shape() {
  local resp="$1" kind="$2"
  local context="${3:-$kind error shape}"
  local why
  if [[ "$kind" != "request" && "$kind" != "execution" ]]; then
    echo "lib.sh: FAIL — ${context}: shape must be 'request' or 'execution', got '$kind'" >&2
    return 1
  fi
  if ! why="$(_err_check shape "$resp" "$kind")"; then
    echo "lib.sh: FAIL — ${context}: $why" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: every error has the $kind shape" >&2
}

# assert_body_not_contains <text> <needle> [context] — the needle occurs nowhere
# in the text; on failure the character offset is printed.
assert_body_not_contains() {
  local text="$1"
  local needle="$2"
  local context="${3:-body}"
  if [[ -n "$needle" && "$text" == *"$needle"* ]]; then
    local before="${text%%"$needle"*}"
    echo "lib.sh: FAIL — ${context}: '$needle' found at offset ${#before}: ${text:${#before}:80}" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: does not contain '$needle'" >&2
}

# assert_json_eq <expected-json> <actual-json> [context] — parsed equality:
# object key order is ignored, list order is significant. Booleans never equal
# numbers (python would treat false == 0 and true == 1 as equal).
assert_json_eq() {
  local expected="$1"
  local actual="$2"
  local context="${3:-json equality}"
  if ! python3 -I -c '
import json, sys

def same(a, b):
    if isinstance(a, bool) or isinstance(b, bool):
        return type(a) is type(b) and a == b
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(same(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    return type(a) is type(b) and a == b or (
        isinstance(a, (int, float)) and isinstance(b, (int, float)) and a == b)

sys.exit(0 if same(json.loads(sys.argv[1]), json.loads(sys.argv[2])) else 1)
' "$expected" "$actual" 2>/dev/null; then
    echo "lib.sh: FAIL — ${context}: expected $expected, got $actual" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: $actual" >&2
}

# json_len <dot.path> — JSON on stdin; the length of the list or object there.
json_len() {
  python3 -I -c '
import json, sys
cur = json.load(sys.stdin)
for part in [p for p in sys.argv[1].strip(".").split(".") if p != ""]:
    cur = cur[int(part)] if isinstance(cur, list) else cur[part]
print(len(cur))
' "$1"
}

# json_keys <dot.path> — JSON on stdin; the keys of the object there, comma
# joined, in document order (response key order follows the selection).
json_keys() {
  python3 -I -c '
import json, sys
cur = json.load(sys.stdin)
for part in [p for p in sys.argv[1].strip(".").split(".") if p != ""]:
    cur = cur[int(part)] if isinstance(cur, list) else cur[part]
print(",".join(cur.keys()))
' "$1"
}

# ---------------------------------------------------------------------------
# Source-call log (lab-only debug endpoint, Ch6 on)
#
# With TRACKING_DEBUG_ENDPOINTS=true each stack records every call into its
# sources (booking, routing, voyage, location, delivery, handling) and serves
# the log at GET /debug/source-calls -> {"calls":[{request, source, op, key,
# startMs, endMs}, ...]} sorted by startMs; DELETE clears it (204). startMs and
# endMs are monotonic milliseconds. A call key reads `source.op:key`, for
# example `booking.getCargo:ABC123`. The log is not part of the schema.
#
# Batch operations (Ch13) use plural names: getCargos, getItineraries,
# getVoyages, getLocations, listEventsFor. Their key is the sorted distinct
# keys joined with `+`, never `,` (assert_source_calls_exactly splits on
# commas), for example `booking.getCargos:ABC123+DEF456`. Ch12 adds
# booking.listCargos (key = the routingStatus filter, or `*` for none) and
# handling.pageEvents (key = trackingId).
#
# Only calls to the owners are logged. A cache hit (Ch16) is not a source call
# and leaves no entry; a bulk operation answered partly from a cache logs only
# the misses, and its key is the misses.
# ---------------------------------------------------------------------------

# graphql_base <url> — the URL without a trailing /graphql.
graphql_base() {
  printf '%s\n' "${1%/graphql}"
}

# source_calls_reset <graphql-url> — DELETE <base>/debug/source-calls; expects 204.
source_calls_reset() {
  local base status
  base="$(graphql_base "$1")"
  _lib_curl_opts
  status="$(curl -sS --max-time "${LGTM_HTTP_TIMEOUT:-30}" "${_LIB_CURL_OPTS[@]}" -o /dev/null -w '%{http_code}' \
    -X DELETE "$base/debug/source-calls")" || return 1
  if [[ "$status" != "204" ]]; then
    echo "lib.sh: FAIL — DELETE $base/debug/source-calls returned HTTP $status (expected 204)" >&2
    return 1
  fi
}

# source_calls <graphql-url> — GET <base>/debug/source-calls; prints {"calls":[...]}.
source_calls() {
  local base
  base="$(graphql_base "$1")"
  _lib_curl_opts
  curl -fsS --max-time "${LGTM_HTTP_TIMEOUT:-30}" "${_LIB_CURL_OPTS[@]}" -H 'Accept: application/json' "$base/debug/source-calls"
}

# source_calls_reset_in <service> — DELETE /debug/source-calls inside the
# service's container (compose_exec_http); expects 204.
source_calls_reset_in() {
  local out status
  out="$(compose_exec_http "$1" DELETE /debug/source-calls)" || return 1
  status="$(status_of "$out")"
  if [[ "$status" != "204" ]]; then
    echo "lib.sh: FAIL — DELETE /debug/source-calls inside $1 returned HTTP $status (expected 204)" >&2
    return 1
  fi
}

# source_calls_in <service> — GET /debug/source-calls inside the service's
# container (compose_exec_http); prints {"calls":[...]}, the same JSON as
# source_calls.
source_calls_in() {
  local out status
  out="$(compose_exec_http "$1" GET /debug/source-calls -H 'Accept: application/json')" || return 1
  status="$(status_of "$out")"
  if [[ "$status" != "200" ]]; then
    echo "lib.sh: FAIL — GET /debug/source-calls inside $1 returned HTTP $status (expected 200)" >&2
    return 1
  fi
  body_of "$out"
}

# _calls_check <mode> <calls-json> [args...] — one python entry point for the
# call-log assertions; prints a reason on failure and returns non-zero.
_calls_check() {
  local mode="$1"
  local calls="$2"
  shift 2
  python3 -I -c '
import json, sys
mode, args = sys.argv[1], sys.argv[2:]
calls = json.load(sys.stdin).get("calls", [])

def name(c):
    return "%s.%s:%s" % (c["source"], c["op"], c["key"])

def one(key):
    hits = [c for c in calls if name(c) == key]
    if len(hits) != 1:
        print("%d call(s) match %s, expected exactly 1 (log: %s)" % (len(hits), key, [name(c) for c in calls]))
        sys.exit(1)
    return hits[0]

if mode == "count":
    source, op, n = args[0], args[1], int(args[2])
    got = len([c for c in calls if (source == "*" or c["source"] == source) and (op == "*" or c["op"] == op)])
    if got != n:
        print("%d call(s) to %s.%s, expected %d (log: %s)" % (got, source, op, n, [name(c) for c in calls]))
        sys.exit(1)
elif mode == "keys":
    source, op = args[0], args[1]
    want = sorted(k for k in args[2].split(",") if k)
    got = sorted(c["key"] for c in calls if c["source"] == source and c["op"] == op)
    if want != got:
        print("keys for %s.%s: expected %s, got %s (log: %s)" % (source, op, want, got, [name(c) for c in calls]))
        sys.exit(1)
elif mode == "exactly":
    want = sorted(k for k in args[0].split(",") if k)
    got = sorted(name(c) for c in calls)
    if want != got:
        print("expected %s, got %s" % (want, got))
        sys.exit(1)
elif mode in ("ordered", "overlap") and args[0] == args[1]:
    print("both keys are %s: a call cannot be compared with itself" % args[0])
    sys.exit(1)
elif mode == "ordered":
    a, b = one(args[0]), one(args[1])
    if not a["endMs"] <= b["startMs"]:
        print("%s ends at %s, after %s starts at %s" % (args[0], a["endMs"], args[1], b["startMs"]))
        sys.exit(1)
elif mode == "overlap":
    a, b = one(args[0]), one(args[1])
    if not (a["startMs"] < b["endMs"] and b["startMs"] < a["endMs"]):
        print("%s [%s,%s] and %s [%s,%s] do not overlap" % (args[0], a["startMs"], a["endMs"], args[1], b["startMs"], b["endMs"]))
        sys.exit(1)
elif mode == "single":
    ids = {c.get("request") for c in calls}
    if len(ids) != 1 or "" in ids or None in ids:
        print("expected one non-empty request id, got %s" % sorted(map(str, ids)))
        sys.exit(1)
elif mode == "requests":
    ids = {c.get("request") for c in calls if c.get("request")}
    if len(ids) != int(args[0]):
        print("expected %s distinct request id(s), got %d: %s" % (args[0], len(ids), sorted(ids)))
        sys.exit(1)
elif mode in ("per_request", "same_per_request"):
    if not calls:
        print("the call log is empty")
        sys.exit(1)
    by = {}
    for c in calls:
        if c.get("request"):
            by.setdefault(c["request"], []).append(name(c))
    if not by:
        print("no entry carries a request id")
        sys.exit(1)
    if mode == "per_request":
        n = int(args[0])
        for rid in sorted(by):
            if len(by[rid]) != n:
                print("request %s made %d call(s), expected %d: %s" % (rid, len(by[rid]), n, sorted(by[rid])))
                sys.exit(1)
    else:
        want = sorted(k for k in args[0].split(",") if k)
        for rid in sorted(by):
            if sorted(by[rid]) != want:
                print("request %s made %s, expected %s" % (rid, sorted(by[rid]), want))
                sys.exit(1)
elif mode == "distinct":
    ids = {c.get("request") for c in calls if c.get("request")}
    if len(ids) < 2:
        print("expected at least 2 distinct request ids, got %s" % sorted(ids))
        sys.exit(1)
' "$mode" "$@" <<<"$calls"
}

# assert_source_call_count <calls-json> <source or *> <op or *> <n> [context]
# `*` for the source matches every source, so `'*' '*' n` is the total.
assert_source_call_count() {
  local calls="$1" source="$2" op="$3" n="$4"
  local context="${5:-$source.$op calls}"
  local why
  if ! why="$(_calls_check count "$calls" "$source" "$op" "$n")"; then
    echo "lib.sh: FAIL — ${context}: $why" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: $n call(s) to $source.$op" >&2
}

# assert_source_call_keys <calls-json> <source> <op> <k1,k2,...> [context] — the
# multiset of `key` values for source.op equals the list (order ignored; an empty
# list means no such calls). Batch keys are `a+b` (sorted distinct keys).
assert_source_call_keys() {
  local calls="$1" source="$2" op="$3" keys="$4"
  local context="${5:-$source.$op keys}"
  local why
  if ! why="$(_calls_check keys "$calls" "$source" "$op" "$keys")"; then
    echo "lib.sh: FAIL — ${context}: $why" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: $source.$op keys [${keys}]" >&2
}

# assert_source_calls_exactly <calls-json> <k1,k2,...> [context] — the multiset
# of `source.op:key` entries equals the list (order ignored; an empty list means
# no calls at all).
assert_source_calls_exactly() {
  local calls="$1" keys="$2"
  local context="${3:-source calls}"
  local why
  if ! why="$(_calls_check exactly "$calls" "$keys")"; then
    echo "lib.sh: FAIL — ${context}: $why" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: exactly [${keys}]" >&2
}

# assert_calls_ordered <calls-json> <keyA> <keyB> [context] — each key matches
# exactly one call, and A finished (endMs) before B started (startMs).
assert_calls_ordered() {
  local calls="$1" a="$2" b="$3"
  local context="${4:-$a before $b}"
  local why
  if ! why="$(_calls_check ordered "$calls" "$a" "$b")"; then
    echo "lib.sh: FAIL — ${context}: $why" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: $a finished before $b started" >&2
}

# assert_calls_overlap <calls-json> <keyA> <keyB> [context] — the two calls were
# in flight at the same time (A.startMs < B.endMs and B.startMs < A.endMs).
assert_calls_overlap() {
  local calls="$1" a="$2" b="$3"
  local context="${4:-$a overlaps $b}"
  local why
  if ! why="$(_calls_check overlap "$calls" "$a" "$b")"; then
    echo "lib.sh: FAIL — ${context}: $why" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: $a and $b overlap" >&2
}

# assert_single_request <calls-json> [context] — every entry carries the same
# non-empty request id: one request, one id across every source call.
assert_single_request() {
  local calls="$1"
  local context="${2:-single request id}"
  local why
  if ! why="$(_calls_check single "$calls")"; then
    echo "lib.sh: FAIL — ${context}: $why" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: one request id" >&2
}

# assert_distinct_requests <calls-json> [context] — at least two distinct
# request ids: two requests did not share one.
assert_distinct_requests() {
  local calls="$1"
  local context="${2:-distinct request ids}"
  local why
  if ! why="$(_calls_check distinct "$calls")"; then
    echo "lib.sh: FAIL — ${context}: $why" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: at least two request ids" >&2
}

# assert_request_count <calls-json> <n> [context] — the number of distinct
# non-empty request ids in the log equals n: one id per request a source saw.
assert_request_count() {
  local calls="$1" n="$2"
  local context="${3:-request count}"
  local why
  if ! why="$(_calls_check requests "$calls" "$n")"; then
    echo "lib.sh: FAIL — ${context}: $why" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: $n distinct request id(s)" >&2
}

# assert_calls_per_request <calls-json> <n> [context] — every distinct non-empty
# request id in the log made exactly n calls. The first offending id and its
# count are printed on failure; an empty log fails.
assert_calls_per_request() {
  local calls="$1" n="$2"
  local context="${3:-calls per request}"
  local why
  if ! why="$(_calls_check per_request "$calls" "$n")"; then
    echo "lib.sh: FAIL — ${context}: $why" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: every request made $n call(s)" >&2
}

# assert_calls_same_per_request <calls-json> <k1,k2,...> [context] — for every
# request id, the multiset of `source.op:key` entries equals the list (order
# ignored). The per-request form of assert_source_calls_exactly, for load runs
# where many requests share one log.
assert_calls_same_per_request() {
  local calls="$1" keys="$2"
  local context="${3:-same calls per request}"
  local why
  if ! why="$(_calls_check same_per_request "$calls" "$keys")"; then
    echo "lib.sh: FAIL — ${context}: $why" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: every request made exactly [${keys}]" >&2
}

# ---------------------------------------------------------------------------
# Test reports (JUnit XML)
# ---------------------------------------------------------------------------

# assert_junit <report-file-or-dir> <expected-tests> [context] — read JUnit XML
# (one file, or every TEST-*.xml in a directory: Maven Surefire writes one per
# class, pytest one junit.xml). The total `tests` equals the expectation and
# `failures`, `errors` and `skipped` are all 0; a failure lists the names of the
# failing tests. Asserting the exact count shows the suite ran what it should.
assert_junit() {
  local report="$1" expected="$2"
  local context="${3:-junit report}"
  local why
  if ! why="$(python3 -I -c '
import glob, os, sys
import xml.etree.ElementTree as ET
path, want = sys.argv[1], int(sys.argv[2])
if os.path.isdir(path):
    files = sorted(glob.glob(os.path.join(path, "TEST-*.xml")))
else:
    files = [path] if os.path.isfile(path) else []
if not files:
    print("no JUnit XML found at %s" % path)
    sys.exit(1)
total = bad = 0
counts = {"failures": 0, "errors": 0, "skipped": 0}
names = []
for f in files:
    try:
        root = ET.parse(f).getroot()
    except (ET.ParseError, OSError) as e:
        print("cannot parse %s: %s" % (f, e))
        sys.exit(1)
    suites = [root] if root.tag == "testsuite" else list(root.iter("testsuite"))
    if root.tag == "testsuites":
        # only leaf suites count, so nested suites are not added twice
        suites = [s for s in suites if not list(s.iter("testsuite"))[1:]]
    for s in suites:
        total += int(s.get("tests", 0))
        for k in counts:
            counts[k] += int(s.get(k, 0))
        for case in s.iter("testcase"):
            for tag in ("failure", "error", "skipped"):
                if case.find(tag) is not None:
                    names.append("%s (%s)" % ((case.get("classname", "") + "." if case.get("classname") else "") + case.get("name", "?"), tag))
                    break
problems = []
if total != want:
    problems.append("%d test(s), expected %d" % (total, want))
for k, v in counts.items():
    if v:
        problems.append("%d %s" % (v, k))
if problems:
    print("; ".join(problems) + (" - " + ", ".join(names) if names else ""))
    sys.exit(1)
' "$report" "$expected")"; then
    echo "lib.sh: FAIL — ${context}: $why" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: $expected test(s), no failures, errors or skips" >&2
}

# ---------------------------------------------------------------------------
# Contract conformance: the live schema vs the canonical SDL
#
# Both stacks are code-first. The live schema is read through standard
# introspection (graphql-inspector takes a URL as a schema pointer) and
# compared with contracts/schema/**/*.graphql.
# ---------------------------------------------------------------------------

# Differences that come from the framework, not from the schema the example
# declares: SmallRye GraphQL (graphql-java) registers the @constraint, @defer,
# @experimental_disableErrorPropagation and @rolesAllowed directives and the
# BigDecimal/BigInteger scalars. They are absent from the canonical SDL and are
# not part of the contract. The names are listed one by one so that a directive
# or type the example itself adds is never filtered. Override
# LGTM_SDL_FRAMEWORK_DIRECTIVES / LGTM_SDL_FRAMEWORK_TYPES (alternations) or
# LGTM_SDL_IGNORE (an extended regex matched against each change line) to widen
# or narrow it.
LGTM_SDL_FRAMEWORK_DIRECTIVES="${LGTM_SDL_FRAMEWORK_DIRECTIVES:-constraint|defer|experimental_disableErrorPropagation|rolesAllowed}"
LGTM_SDL_FRAMEWORK_TYPES="${LGTM_SDL_FRAMEWORK_TYPES:-BigDecimal|BigInteger}"
LGTM_SDL_IGNORE="${LGTM_SDL_IGNORE:-Directive (${LGTM_SDL_FRAMEWORK_DIRECTIVES}) was (removed|added)\$|Type (${LGTM_SDL_FRAMEWORK_TYPES}) was (removed|added)\$}"

# In the canonical -> live direction these removals are the part of the
# contract a slice does not serve yet: whole types, whole output fields, and
# the mutation/subscription roots. Anything else that "was removed" (an
# argument of a served field, an enum value, a union member, an input field)
# is drift in what the stack does serve.
LGTM_SDL_SLICE_REMOVALS='✖ +(Type [A-Za-z_]+ was removed|Field [A-Za-z_]+ was removed from (object|interface) type [A-Za-z_]+|Schema (mutation|subscription) type [A-Za-z_]+ was removed\.)$'

# _sdl_diff <old> <new> — run `graphql-inspector diff` and print its output.
# Fails loudly when the tool itself could not run or load a schema (as opposed
# to reporting changes), so a connection error can never read as "conforms".
#
# LGTM_CACERT: exported to the tool as NODE_EXTRA_CA_CERTS so it trusts the
# endpoint's private CA over https. LGTM_BEARER: sent to the tool as
# --header "Authorization: Bearer ..." (inspector splits the header at the
# first colon). Both unset: the tool runs exactly as before.
_sdl_diff() {
  local out rc=0
  local -a hdr=()
  if [[ -n "${LGTM_BEARER:-}" ]]; then
    hdr=(--header "Authorization: Bearer $LGTM_BEARER")
  fi
  if [[ -n "${LGTM_CACERT:-}" ]]; then
    export NODE_EXTRA_CA_CERTS="$LGTM_CACERT"
  fi
  out="$("$CONTRACTS_DIR/node_modules/.bin/graphql-inspector" diff "${hdr[@]}" "$1" "$2" 2>&1)" || rc=$?
  if ! grep -qE "No changes detected|Detected the following changes" <<<"$out"; then
    echo "lib.sh: FAIL — graphql-inspector could not compare '$1' with '$2' (exit $rc):" >&2
    echo "$out" >&2
    return 2
  fi
  printf '%s\n' "$out"
}

# assert_sdl_conforms <pointer> [context]
#
# <pointer> is a graphql-inspector schema pointer: a GraphQL endpoint URL (read
# by introspection) or a file or glob of SDL (for example a schema a stack
# exported).
#
# Checks that a stack serving a slice of the schema agrees with the canonical
# SDL, in two directions:
#
#   live -> canonical  (live is "old"): any BREAKING change means the stack
#     exposes something the contract lacks (an extra field, type or argument)
#     or is stricter than the contract (non-null live where the contract is
#     nullable: Cargo.itinerary Itinerary -> Itinerary!).
#   canonical -> live  (canonical is "old"): any BREAKING change other than
#     a slice removal (LGTM_SDL_SLICE_REMOVALS: a whole type, a whole output
#     field, an unserved root) means something the stack does expose differs
#     from the contract: nullable live where the contract is non-null, a
#     different type, a missing argument or enum value. Any description change
#     on a type, field or argument both sides have also fails.
#
# Framework-injected differences are filtered through LGTM_SDL_IGNORE.
# The diff covers types, fields, arguments and enum values. A scalar's
# @specifiedBy is asserted by verify.sh directly, with
# `__type(name:) { specifiedByURL }`.
assert_sdl_conforms() {
  local url="$1"
  local context="${2:-$url}"
  local fwd rev bad_fwd bad_rev rc=0
  ensure_contracts_tools || return 1
  fwd="$(_sdl_diff "$url" "$CANONICAL_SDL_GLOB")" || rc=$?
  (( rc == 0 )) || return 1
  rev="$(_sdl_diff "$CANONICAL_SDL_GLOB" "$url")" || rc=$?
  (( rc == 0 )) || return 1

  bad_fwd="$(grep '✖' <<<"$fwd" | grep -vE "$LGTM_SDL_IGNORE" || true)"
  bad_rev="$( { grep '✖' <<<"$rev" | grep -vE "$LGTM_SDL_SLICE_REMOVALS|$LGTM_SDL_IGNORE"
                grep -E '\[log\] +(⚠|✔) .*[Dd]escription' <<<"$rev"; } || true)"
  if [[ -n "$bad_fwd" ]]; then
    echo "lib.sh: FAIL — ${context}: the live schema exposes what the canonical SDL lacks or loosens it:" >&2
    echo "$bad_fwd" >&2
    return 1
  fi
  if [[ -n "$bad_rev" ]]; then
    echo "lib.sh: FAIL — ${context}: the live schema differs from the canonical SDL in what it serves:" >&2
    echo "$bad_rev" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: live schema conforms to the canonical SDL (slice)" >&2
}

# assert_sdl_equals <graphql-url> [context]
#
# For the complete schema (the final project): the live schema must equal the
# canonical SDL, with no change in either direction apart from the filtered
# framework noise.
assert_sdl_equals() {
  local url="$1"
  local context="${2:-$url}"
  local fwd rev rc=0 left
  ensure_contracts_tools || return 1
  fwd="$(_sdl_diff "$url" "$CANONICAL_SDL_GLOB")" || rc=$?
  (( rc == 0 )) || return 1
  rev="$(_sdl_diff "$CANONICAL_SDL_GLOB" "$url")" || rc=$?
  (( rc == 0 )) || return 1
  # Every reported change line (breaking, dangerous or safe) except the filtered
  # framework additions/removals counts as a difference. @specifiedBy lines are
  # filtered here; verify.sh asserts a scalar's specifiedByURL (see
  # assert_sdl_conforms).
  left="$( { grep -E '\[log\] +(✖|⚠|✔)' <<<"$fwd"; grep -E '\[log\] +(✖|⚠|✔)' <<<"$rev"; } \
          | grep -vE "$LGTM_SDL_IGNORE|Directive specifiedBy was (removed from|added to) scalar" || true)"
  if [[ -n "$left" ]]; then
    echo "lib.sh: FAIL — ${context}: live schema is not identical to the canonical SDL:" >&2
    echo "$left" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: live schema equals the canonical SDL" >&2
}

# assert_sdl_same <pointerA> <pointerB> [context]
#
# Two stacks, one schema: diffs A -> B and B -> A and fails if any change line
# (breaking, dangerous or safe) remains after the framework noise filter
# (LGTM_SDL_IGNORE) and the @specifiedBy filter. Both pointers may be URLs or
# files, as for assert_sdl_conforms.
assert_sdl_same() {
  local a="$1"
  local b="$2"
  local context="${3:-$a vs $b}"
  local fwd rev rc=0 left
  ensure_contracts_tools || return 1
  fwd="$(_sdl_diff "$a" "$b")" || rc=$?
  (( rc == 0 )) || return 1
  rev="$(_sdl_diff "$b" "$a")" || rc=$?
  (( rc == 0 )) || return 1
  left="$( { grep -E '\[log\] +(✖|⚠|✔)' <<<"$fwd"; grep -E '\[log\] +(✖|⚠|✔)' <<<"$rev"; } \
          | grep -vE "$LGTM_SDL_IGNORE|Directive specifiedBy was (removed from|added to) scalar" || true)"
  if [[ -n "$left" ]]; then
    echo "lib.sh: FAIL — ${context}: the two schemas differ:" >&2
    echo "$left" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: the two schemas are identical" >&2
}

# assert_sdl_drift <pointer> <needle> [context]
#
# The negative test of the gate: passes only when assert_sdl_conforms FAILS on
# <pointer> and its report contains <needle> (the changed type or field). A
# tool error (the comparison could not run) is a FAIL, never "drift detected".
assert_sdl_drift() {
  local pointer="$1"
  local needle="$2"
  local context="${3:-$pointer}"
  local out rc=0
  # A fixed context, so the needle is matched against the report and never
  # against a caller's context string that happens to contain it.
  out="$(assert_sdl_conforms "$pointer" "sdl-drift" 2>&1)" || rc=$?
  if (( rc == 0 )); then
    echo "lib.sh: FAIL — ${context}: expected drift containing '$needle', but the schema conforms" >&2
    return 1
  fi
  if grep -q "could not compare" <<<"$out"; then
    echo "lib.sh: FAIL — ${context}: the comparison itself failed, so no drift verdict:" >&2
    echo "$out" >&2
    return 1
  fi
  if ! grep -v '^lib.sh: ' <<<"$out" | grep -qF -- "$needle"; then
    echo "lib.sh: FAIL — ${context}: drift was reported but does not mention '$needle':" >&2
    echo "$out" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: drift detected as expected ('$needle')" >&2
}

# ---------------------------------------------------------------------------
# Deprecation state (assert_sdl_conforms does not compare it)
# ---------------------------------------------------------------------------

# _field_deprecation <url> <Type> <field> — prints "<isDeprecated>|<reason>"
# (true|false, reason may be null/empty), or "missing" when the type or field
# does not exist. One __type request with includeDeprecated:true.
_field_deprecation() {
  local url="$1" type="$2" field="$3" resp
  # shellcheck disable=SC2016  # $n is a GraphQL variable, not a shell expansion
  resp="$(gql "$url" 'query($n: String!) { __type(name: $n) { fields(includeDeprecated: true) { name isDeprecated deprecationReason } } }' \
    "{\"n\":\"$type\"}")" || return 1
  python3 -I -c '
import json, sys
t = (json.load(sys.stdin).get("data") or {}).get("__type") or {}
for f in t.get("fields") or []:
    if f.get("name") == sys.argv[1]:
        print("%s|%s" % ("true" if f.get("isDeprecated") is True else "false", f.get("deprecationReason") or ""))
        sys.exit(0)
print("missing")
' "$field" <<<"$resp"
}

# assert_deprecated <url> <Type> <field> <reason> [context] — the field exists,
# isDeprecated is true, and deprecationReason equals the reason exactly.
assert_deprecated() {
  local url="$1" type="$2" field="$3" reason="$4"
  local context="${5:-$type.$field deprecated}"
  local got
  got="$(_field_deprecation "$url" "$type" "$field")" || return 1
  if [[ "$got" == "missing" ]]; then
    echo "lib.sh: FAIL — ${context}: $type.$field does not exist" >&2
    return 1
  fi
  if [[ "${got%%|*}" != "true" ]]; then
    echo "lib.sh: FAIL — ${context}: $type.$field is not deprecated" >&2
    return 1
  fi
  if [[ "${got#*|}" != "$reason" ]]; then
    echo "lib.sh: FAIL — ${context}: $type.$field deprecation reason is '${got#*|}', expected '$reason'" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: $type.$field is deprecated ('$reason')" >&2
}

# assert_not_deprecated <url> <Type> <field> [context] — the field exists and
# isDeprecated is false.
assert_not_deprecated() {
  local url="$1" type="$2" field="$3"
  local context="${4:-$type.$field not deprecated}"
  local got
  got="$(_field_deprecation "$url" "$type" "$field")" || return 1
  if [[ "$got" == "missing" ]]; then
    echo "lib.sh: FAIL — ${context}: $type.$field does not exist" >&2
    return 1
  fi
  if [[ "${got%%|*}" != "false" ]]; then
    echo "lib.sh: FAIL — ${context}: $type.$field is deprecated ('${got#*|}')" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: $type.$field is not deprecated" >&2
}

# ---------------------------------------------------------------------------
# The breaking-change gate on fixtures (contracts/scripts/breaking.sh)
# ---------------------------------------------------------------------------

# run_gate <base-dir> <new-dir> [rule,...] — run the gate with BASE_DIR, NEW_DIR
# and BREAKING_RULES; print the combined output and return the gate's exit code
# (0 ok, 1 breaking, 2 setup error). GITHUB_ACTIONS is unset so a fixture run
# never emits ::warning annotations into a CI log.
run_gate() {
  local base="$1" new="$2" rules="${3:-}"
  ensure_contracts_tools || return 2
  env -u GITHUB_ACTIONS BASE_DIR="$base" NEW_DIR="$new" BREAKING_RULES="$rules" \
    bash "$CONTRACTS_DIR/scripts/breaking.sh" 2>&1
}

# assert_gate <expected-rc> <needle> <base-dir> <new-dir> [rules] [context]
#
# Passes only when the gate's exit code equals <expected-rc> AND the needle is
# in its output (lines starting `lib.sh:` excluded, so a context string never
# counts). When the exit code differs and the output shows the tool itself
# failed ("could not", "Error:"), or the code is neither 0 nor 1, it is reported
# as a tool error, not as a gate verdict.
assert_gate() {
  local expected="$1" needle="$2" base="$3" new="$4"
  local rules="${5:-}"
  local context="${6:-gate $needle}"
  local out rc=0
  out="$(run_gate "$base" "$new" "$rules")" || rc=$?
  if (( rc != expected )) && { (( rc > 1 )) || grep -qE 'could not|Error:' <<<"$out"; }; then
    echo "lib.sh: FAIL — ${context}: the gate itself failed (exit $rc, expected $expected):" >&2
    echo "$out" >&2
    return 1
  fi
  if (( rc != expected )); then
    echo "lib.sh: FAIL — ${context}: gate exit $rc, expected $expected:" >&2
    echo "$out" >&2
    return 1
  fi
  if ! grep -v '^lib.sh:' <<<"$out" | grep -qF -- "$needle"; then
    echo "lib.sh: FAIL — ${context}: gate exit $rc as expected but the output lacks '$needle':" >&2
    echo "$out" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: gate exit $rc, found '$needle'" >&2
}

# documents_validate <glob> [extra-args...] — validate client documents (queries,
# mutations, fragments) against the canonical SDL with `graphql-inspector
# validate`. The glob is expanded by the tool and is relative to the working
# directory. Prints the combined output and returns the tool's exit code (0 when
# every document is valid, 1 when one is not), so a caller asserts success or
# failure and the needle, as it does with run_gate.
documents_validate() {
  local documents="$1"
  shift
  ensure_contracts_tools || return 2
  "$CONTRACTS_DIR/node_modules/.bin/graphql-inspector" validate "$documents" "$CANONICAL_SDL_GLOB" "$@" 2>&1
}

# ---------------------------------------------------------------------------
# Trace ids and traceparent (Ch19)
#
# A script picks the trace id, sends it as a W3C traceparent header
# (LGTM_TRACEPARENT, see _lib_curl_opts), then reads that trace back from the
# backend by id, so a telemetry assertion never depends on "the latest trace".
# ---------------------------------------------------------------------------

# new_trace_id — 32 lowercase hex characters.
new_trace_id() {
  python3 -I -c '
import secrets
print(secrets.token_hex(16))
'
}

# traceparent_for <trace-id> — the W3C traceparent value 00-<trace-id>-<span id>-01
# (sampled) with a fresh 16-hex span id. Export it as LGTM_TRACEPARENT.
traceparent_for() {
  local trace_id="$1"
  if [[ ! "$trace_id" =~ ^[0-9a-f]{32}$ ]]; then
    echo "lib.sh: FAIL — traceparent_for: '$trace_id' is not 32 lowercase hex characters" >&2
    return 1
  fi
  python3 -I -c '
import secrets, sys
print("00-%s-%s-01" % (sys.argv[1], secrets.token_hex(8)))
' "$trace_id"
}

# ---------------------------------------------------------------------------
# Tempo, Prometheus and Loki (grafana/otel-lgtm), read over HTTP. These calls
# carry LGTM_CACERT but never the bearer token, traceparent or LGTM_HEADERS:
# a backend query is not part of the trace under test.
# ---------------------------------------------------------------------------

# _tempo_normalize — a Tempo trace response on stdin, printed as
#   {"spans":[{"name","spanId","parentSpanId","service","kind","status",
#              "attributes":{...}}]}
# Both response shapes are read: GET /api/traces/<id> answers {"batches":[...]},
# GET /api/v2/traces/<id> answers {"trace":{"resourceSpans":[...]}}. Ids are
# printed as lowercase hex whether Tempo sent hex or base64 (the protobuf JSON
# mapping of bytes). kind is SERVER, CLIENT, INTERNAL, ...; status is OK, ERROR
# or UNSET; attribute values are plain JSON values. Exits non-zero when the
# body holds no trace document.
_tempo_normalize() {
  python3 -I -c '
import base64, binascii, json, re, sys

def hexid(v):
    if not v:
        return ""
    if re.fullmatch(r"[0-9a-fA-F]{16}|[0-9a-fA-F]{32}", v):
        return v.lower()
    try:
        return binascii.hexlify(base64.b64decode(v + "=" * (-len(v) % 4))).decode()
    except Exception:
        return v

def value(v):
    if "stringValue" in v:
        return v["stringValue"]
    if "intValue" in v:
        return int(v["intValue"])
    if "boolValue" in v:
        return bool(v["boolValue"])
    if "doubleValue" in v:
        return float(v["doubleValue"])
    if "arrayValue" in v:
        return [value(x) for x in v["arrayValue"].get("values", [])]
    if "kvlistValue" in v:
        return {kv["key"]: value(kv["value"]) for kv in v["kvlistValue"].get("values", [])}
    return None

def attrs(items):
    return {kv["key"]: value(kv.get("value", {})) for kv in items or []}

STATUS = {0: "UNSET", 1: "OK", 2: "ERROR"}
KINDS = ["UNSPECIFIED", "INTERNAL", "SERVER", "CLIENT", "PRODUCER", "CONSUMER"]

def status(st):
    code = (st or {}).get("code", 0)
    if isinstance(code, str):
        return code.replace("STATUS_CODE_", "") or "UNSET"
    return STATUS.get(code, "UNSET")

def kind(k):
    if isinstance(k, int):
        return KINDS[k] if 0 <= k < len(KINDS) else "UNSPECIFIED"
    return (k or "SPAN_KIND_UNSPECIFIED").replace("SPAN_KIND_", "")

doc = json.load(sys.stdin)
if isinstance(doc.get("trace"), dict):
    doc = doc["trace"]
batches = doc.get("batches") or doc.get("resourceSpans")
if batches is None:
    sys.exit(1)
spans = []
for batch in batches:
    service = attrs(batch.get("resource", {}).get("attributes")).get("service.name", "")
    scopes = batch.get("scopeSpans") or batch.get("instrumentationLibrarySpans") or []
    for scope in scopes:
        for sp in scope.get("spans", []):
            spans.append({
                "name": sp.get("name", ""),
                "spanId": hexid(sp.get("spanId")),
                "parentSpanId": hexid(sp.get("parentSpanId")),
                "service": service,
                "kind": kind(sp.get("kind")),
                "status": status(sp.get("status")),
                "attributes": attrs(sp.get("attributes")),
            })
print(json.dumps({"spans": spans}, separators=(",", ":")))
'
}

# tempo_trace <tempo-base> <trace-id> [timeout_secs] [min-spans]
#
# Polls GET <base>/api/traces/<id> (and /api/v2/traces/<id> when that answers
# 404) until the trace holds at least min-spans spans (default 1), then prints
# it through _tempo_normalize. FAIL after timeout_secs (default 60). The trace
# id is the one the script sent, so the answer is that request's trace.
tempo_trace() {
  local base="${1%/}" trace_id="$2"
  local timeout="${3:-60}" min_spans="${4:-1}"
  local waited=0 interval=2
  local tmp status path doc count=0

  if [[ ! "$trace_id" =~ ^[0-9a-fA-F]{32}$ ]]; then
    echo "lib.sh: FAIL — tempo_trace: '$trace_id' is not a 32-hex trace id" >&2
    return 1
  fi
  tmp="$(mktemp)"
  _lib_curl_opts --no-bearer --no-trace
  echo "lib.sh: waiting for trace $trace_id in Tempo (>= $min_spans span(s), timeout ${timeout}s) ..." >&2
  while (( waited < timeout )); do
    for path in /api/traces /api/v2/traces; do
      status="$(curl -sS --max-time 10 "${_LIB_CURL_OPTS[@]}" -o "$tmp" -w '%{http_code}' \
        "$base$path/$trace_id" 2>/dev/null || true)"
      [[ "$status" == "404" ]] && continue
      break
    done
    if [[ "$status" == "200" ]] && doc="$(_tempo_normalize <"$tmp" 2>/dev/null)"; then
      count="$(json_len spans <<<"$doc")"
      if (( count >= min_spans )); then
        rm -f "$tmp"
        echo "lib.sh: trace $trace_id has $count span(s) after ${waited}s" >&2
        printf '%s\n' "$doc"
        return 0
      fi
    fi
    sleep "$interval"
    waited=$(( waited + interval ))
  done

  rm -f "$tmp"
  echo "lib.sh: FAIL — trace $trace_id did not reach $min_spans span(s) in Tempo within ${timeout}s (last status: ${status:-none}, spans: $count)" >&2
  return 1
}

# _span_check <mode> <trace-json> [args...] — one python entry point for the
# span assertions over a tempo_trace document; prints a reason on failure and
# returns non-zero. Name and attribute-key arguments are regular expressions
# (re.search); attribute values compare as text (true/false for booleans).
_span_check() {
  local mode="$1"
  local trace="$2"
  shift 2
  python3 -I -c '
import json, re, sys
mode, args = sys.argv[1], sys.argv[2:]
spans = json.load(sys.stdin).get("spans", [])
by_id = {s["spanId"]: s for s in spans}

def label(s):
    return "%s[%s]" % (s["name"], s["service"])

def matching(rx):
    return [s for s in spans if re.search(rx, s["name"])]

def text(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    return str(v)

def names():
    return [label(s) for s in spans]

if mode == "count":
    rx, low = args[0], int(args[1] or 1)
    high = int(args[2]) if args[2] else None
    got = len(matching(rx))
    if got < low or (high is not None and got > high):
        print("%d span(s) match /%s/, expected %d..%s (spans: %s)" % (got, rx, low, high if high is not None else "any", names()))
        sys.exit(1)
elif mode == "attr":
    rx, key, want = args
    hits = matching(rx)
    if not hits:
        print("no span matches /%s/ (spans: %s)" % (rx, names()))
        sys.exit(1)
    if not any(key in s["attributes"] and text(s["attributes"][key]) == want for s in hits):
        print("no span matching /%s/ has %s=%s (got: %s)" % (rx, key, want, [text(s["attributes"].get(key, "<absent>")) for s in hits]))
        sys.exit(1)
elif mode == "attr_absent":
    rx = args[0]
    bad = ["%s has %s" % (label(s), k) for s in spans for k in s["attributes"] if re.search(rx, k)]
    if bad:
        print("attribute key /%s/ occurs: %s" % (rx, bad))
        sys.exit(1)
elif mode == "descends":
    child_rx, anc_rx = args
    kids = matching(child_rx)
    if not kids:
        print("no span matches /%s/ (spans: %s)" % (child_rx, names()))
        sys.exit(1)
    for kid in kids:
        seen, cur, found = set(), kid, False
        while cur["parentSpanId"] and cur["parentSpanId"] not in seen:
            seen.add(cur["parentSpanId"])
            cur = by_id.get(cur["parentSpanId"])
            if cur is None:
                break
            if re.search(anc_rx, cur["name"]):
                found = True
                break
        if not found:
            print("%s has no ancestor matching /%s/" % (label(kid), anc_rx))
            sys.exit(1)
elif mode == "status":
    rx, want = args
    hits = matching(rx)
    if not any(s["status"] == want for s in hits):
        print("no span matching /%s/ has status %s (got: %s)" % (rx, want, [(s["name"], s["status"]) for s in hits]))
        sys.exit(1)
elif mode == "not_contains":
    rx, key, needle = args
    hits = matching(rx)
    if not hits:
        print("no span matches /%s/ (spans: %s)" % (rx, names()))
        sys.exit(1)
    bad = [label(s) for s in hits if needle in text(s["attributes"].get(key, ""))]
    if bad:
        print("attribute %s contains the needle in: %s" % (key, bad))
        sys.exit(1)
' "$mode" "$@" <<<"$trace"
}

# assert_span <trace> <name-regex> [min] [max] [context] — the number of spans
# whose name matches is within [min, max] (defaults 1 and unbounded).
assert_span() {
  local trace="$1" rx="$2" low="${3:-1}" high="${4:-}"
  local context="${5:-span /$rx/}"
  local why
  if ! why="$(_span_check count "$trace" "$rx" "$low" "$high")"; then
    echo "lib.sh: FAIL — ${context}: $why" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: /$rx/ occurs ${low}..${high:-any} time(s)" >&2
}

# assert_span_attr <trace> <name-regex> <attr> <expected> [context] — some span
# matching the name has the attribute with this value.
assert_span_attr() {
  local trace="$1" rx="$2" attr="$3" expected="$4"
  local context="${5:-span /$rx/ $attr}"
  local why
  if ! why="$(_span_check attr "$trace" "$rx" "$attr" "$expected")"; then
    echo "lib.sh: FAIL — ${context}: $why" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: $attr = '$expected'" >&2
}

# assert_span_attr_absent <trace> <attr-regex> [context] — no span has an
# attribute whose key matches the regular expression.
assert_span_attr_absent() {
  local trace="$1" rx="$2"
  local context="${3:-no span attribute /$rx/}"
  local why
  if ! why="$(_span_check attr_absent "$trace" "$rx")"; then
    echo "lib.sh: FAIL — ${context}: $why" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: no attribute key matches /$rx/" >&2
}

# assert_span_descends <trace> <child-regex> <ancestor-regex> [context] — there
# is at least one span matching the child regex, and every one has an ancestor
# whose name matches the other regex.
assert_span_descends() {
  local trace="$1" child="$2" ancestor="$3"
  local context="${4:-/$child/ under /$ancestor/}"
  local why
  if ! why="$(_span_check descends "$trace" "$child" "$ancestor")"; then
    echo "lib.sh: FAIL — ${context}: $why" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: /$child/ spans descend from /$ancestor/" >&2
}

# assert_span_status <trace> <name-regex> <OK|ERROR|UNSET> [context] — some
# span matching the name has that status.
assert_span_status() {
  local trace="$1" rx="$2" want="$3"
  local context="${4:-span /$rx/ status}"
  local why
  if ! why="$(_span_check status "$trace" "$rx" "$want")"; then
    echo "lib.sh: FAIL — ${context}: $why" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: status $want" >&2
}

# assert_attr_not_contains <trace> <name-regex> <attr> <needle> [context] — at
# least one span matches the name, and the attribute of every matching span
# does not contain the needle (a span without the attribute passes). Use it to
# prove a value never reaches telemetry.
assert_attr_not_contains() {
  local trace="$1" rx="$2" attr="$3" needle="$4"
  local context="${5:-span /$rx/ $attr}"
  local why
  if ! why="$(_span_check not_contains "$trace" "$rx" "$attr" "$needle")"; then
    echo "lib.sh: FAIL — ${context}: $why" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: $attr never contains the needle" >&2
}

# _prom_sample <result-json> — the first sample value of a prom_query result,
# or nothing when the result is empty.
_prom_sample() {
  python3 -I -c '
import json, sys
res = json.load(sys.stdin)
if res:
    print(res[0]["value"][1])
' <<<"$1"
}

# prom_query <prom-base> <promql>
#
# Instant query: GET <base>/api/v1/query; prints the data.result JSON (a list
# of {metric, value:[ts, "number"]}, possibly empty). Non-zero when the request
# fails or Prometheus does not answer status "success".
prom_query() {
  local base="${1%/}" promql="$2"
  local out
  _lib_curl_opts --no-bearer --no-trace
  out="$(curl -fsS --max-time "${LGTM_HTTP_TIMEOUT:-30}" "${_LIB_CURL_OPTS[@]}" -G \
    --data-urlencode "query=$promql" "$base/api/v1/query")" || return 1
  python3 -I -c '
import json, sys
doc = json.load(sys.stdin)
if doc.get("status") != "success":
    sys.stderr.write("lib.sh: FAIL — prom_query: status %s: %s\n" % (doc.get("status"), doc.get("error", "")))
    sys.exit(1)
print(json.dumps(doc["data"]["result"], separators=(",", ":")))
' <<<"$out"
}

# wait_for_metric <prom-base> <promql> <min> [timeout_secs]
#
# Polls prom_query until the first sample's value is >= min; FAIL after
# timeout_secs (default 120, a scrape interval or two).
wait_for_metric() {
  local base="$1" promql="$2" min="$3"
  local timeout="${4:-120}"
  local waited=0 interval=3
  local res value="" ok

  echo "lib.sh: waiting for $promql >= $min (timeout ${timeout}s) ..." >&2
  while (( waited < timeout )); do
    if res="$(prom_query "$base" "$promql" 2>/dev/null)"; then
      value="$(_prom_sample "$res")"
      if [[ -n "$value" ]]; then
        ok="$(python3 -I -c '
import sys
print("yes" if float(sys.argv[1]) >= float(sys.argv[2]) else "no")
' "$value" "$min")"
        if [[ "$ok" == "yes" ]]; then
          echo "lib.sh: ok — $promql = $value (>= $min) after ${waited}s" >&2
          return 0
        fi
      fi
    fi
    sleep "$interval"
    waited=$(( waited + interval ))
  done

  echo "lib.sh: FAIL — $promql did not reach $min within ${timeout}s (last: '${value:-no sample}')" >&2
  return 1
}

# assert_metric_eq <prom-base> <promql> <value> [context] — the first sample's
# value equals the number.
assert_metric_eq() {
  local base="$1" promql="$2" expected="$3"
  local context="${4:-$promql}"
  local res value ok
  res="$(prom_query "$base" "$promql")" || return 1
  value="$(_prom_sample "$res")"
  if [[ -z "$value" ]]; then
    echo "lib.sh: FAIL — ${context}: $promql returned no sample" >&2
    return 1
  fi
  ok="$(python3 -I -c '
import sys
print("yes" if float(sys.argv[1]) == float(sys.argv[2]) else "no")
' "$value" "$expected")"
  if [[ "$ok" != "yes" ]]; then
    echo "lib.sh: FAIL — ${context}: $promql is $value, expected $expected" >&2
    return 1
  fi
  echo "lib.sh: ok — ${context}: $promql = $value" >&2
}

# loki_wait <loki-base> <logql> [timeout_secs] [min-lines]
#
# Polls GET <base>/loki/api/v1/query_range (default window: the last hour, up
# to 1000 lines, oldest first) until at least min-lines (default 1) log lines
# match; prints the lines, one per output line. FAIL after timeout_secs
# (default 60).
loki_wait() {
  local base="${1%/}" logql="$2"
  local timeout="${3:-60}" min_lines="${4:-1}"
  local waited=0 interval=3
  local out lines="" count=0

  _lib_curl_opts --no-bearer --no-trace
  echo "lib.sh: waiting for >= $min_lines Loki line(s) of $logql (timeout ${timeout}s) ..." >&2
  while (( waited < timeout )); do
    if out="$(curl -fsS --max-time 10 "${_LIB_CURL_OPTS[@]}" -G \
          --data-urlencode "query=$logql" --data-urlencode 'limit=1000' \
          --data-urlencode 'direction=forward' "$base/loki/api/v1/query_range" 2>/dev/null)"; then
      lines="$(python3 -I -c '
import json, sys
doc = json.load(sys.stdin)
rows = [(v[0], v[1]) for st in doc["data"]["result"] for v in st["values"]]
for _, line in sorted(rows):
    print(line.replace("\n", " "))
' <<<"$out" 2>/dev/null || true)"
      count=0
      [[ -n "$lines" ]] && count="$(grep -c '' <<<"$lines")"
      if (( count >= min_lines )); then
        echo "lib.sh: Loki returned $count line(s) after ${waited}s" >&2
        printf '%s\n' "$lines"
        return 0
      fi
    fi
    sleep "$interval"
    waited=$(( waited + interval ))
  done

  echo "lib.sh: FAIL — Loki returned $count of $min_lines line(s) for $logql within ${timeout}s" >&2
  return 1
}

# ---------------------------------------------------------------------------
# Server-sent events (Ch21)
# ---------------------------------------------------------------------------

# sse_collect <url> <max-secs> <max-events> [curl-args...]
#
# Reads a text/event-stream with `curl -sN --max-time <max-secs>` and prints one
# JSON line per event, {"event","id","data"}, as soon as the event is complete.
# Comment lines (": ...") are skipped; "event" defaults to "message"; "id" is
# the event's own id or ""; several data lines join with a newline. Stops after
# max-events events (curl is then closed early, or ends at max-secs). Pass the request headers as curl arguments, for example
# -H 'Accept: text/event-stream'. LGTM_CACERT, LGTM_BEARER, LGTM_TRACEPARENT and
# LGTM_HEADERS apply. Reaching max-secs, or max-events, is not an error; the
# exit status is non-zero only when the transport fails (connection refused,
# TLS, DNS).
sse_collect() {
  local url="$1" max_secs="$2" max_events="$3"
  shift 3
  local rc_file err_file curl_rc py_rc=0

  rc_file="$(mktemp)"
  err_file="$(mktemp)"
  _lib_curl_opts
  { curl -sSN --max-time "$max_secs" "${_LIB_CURL_OPTS[@]}" "$@" "$url" 2>"$err_file" || echo "$?" >"$rc_file"; true; } \
    | python3 -I -c '
import json, sys
limit = int(sys.argv[1])
event, ident, data, seen = "", "", [], False
sent = 0
for raw in sys.stdin.buffer:
    line = raw.decode("utf-8", "replace").rstrip("\r\n")
    if line == "":
        if seen:
            print(json.dumps({"event": event or "message", "id": ident, "data": "\n".join(data)}), flush=True)
            sent += 1
            if sent >= limit:
                break
        event, ident, data, seen = "", "", [], False
        continue
    if line.startswith(":"):
        continue
    name, _, value = line.partition(":")
    if value.startswith(" "):
        value = value[1:]
    if name == "event":
        event, seen = value, True
    elif name == "id":
        ident, seen = value, True
    elif name == "data":
        data.append(value)
        seen = True
' "$max_events" || py_rc=$?
  curl_rc="$(cat "$rc_file")"
  if (( py_rc != 0 )); then
    echo "lib.sh: FAIL — sse_collect: could not parse the stream from $url" >&2
    rm -f "$rc_file" "$err_file"
    return 1
  fi
  case "${curl_rc:-0}" in
    0|23|28|141) rm -f "$rc_file" "$err_file"; return 0 ;;
    *)
      echo "lib.sh: FAIL — sse_collect: curl exited ${curl_rc} for $url: $(cat "$err_file")" >&2
      rm -f "$rc_file" "$err_file"
      return 1
      ;;
  esac
}
