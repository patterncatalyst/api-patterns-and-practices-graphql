#!/usr/bin/env bash
# examples/23-testing/verify.sh
#
# Ch23 Testing GraphQL APIs: six layers, each proving something the others do not.
#
#   schema, resolver unit, operation integration   the in-process suites, run in the
#       `test` stage of each Containerfile (Quarkus: mvn verify; Python: pytest);
#       the exact test count comes from the JUnit XML, and each suite exports
#       the schema it built
#   contract       that exported schema, and the live endpoint, diffed against
#                  contracts/schema/
#   client document  documents/ are Chapter 22's operations: the same text,
#                  valid against the contract; the document that selects
#                  Cargo.weight is refused; coverage counts which fields clients use
#   load           k6 sends the documents at volume with exact numbers of iterations;
#                  verify.sh reads the source-call log per request id afterwards
#
# The load runs assert correctness invariants (no transport failure, every check
# true, every call count per request unchanged under concurrency). Latency is
# printed and never asserted.
#
# The queries are read from documents/. Only the anchors are written here.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../_lib/lib.sh
source "$SCRIPT_DIR/../_lib/lib.sh"

PROJECT="gql-ch23-testing"
COMPOSE_FILE="$SCRIPT_DIR/compose.yaml"
DOCS="$SCRIPT_DIR/documents"
CH22_OPERATIONS="$SCRIPT_DIR/../22-client-integration/clients/js/src/operations.graphql"
CH22_FIXTURE="$SCRIPT_DIR/../22-client-integration/clients/js/fixtures/cargo-weight.graphql"

# The exact number of tests each suite runs: a test that disappears fails here.
QUARKUS_TESTS=22
PYTHON_TESTS=18

# Scratch directories for the reports the test and load containers write.
# They are mode 0777 because the images run as UID 185, 1001 and root.
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/ch23-verify.XXXXXX")"
chmod 0777 "$SCRATCH"
on_exit "rm -rf '$SCRATCH'"

# --- local helpers ----------------------------------------------------------

# same_operations — every documents/<file> equals the same-named operation of
# Chapter 22's operations.graphql, after comments and whitespace are dropped.
same_operations() {
  python3 -I -c '
import re, sys
ops_file, docs = sys.argv[1], sys.argv[2]
files = {
    "TrackCargo": "track-cargo",
    "TrackCargoBrief": "track-cargo-brief",
    "RegisterHandling": "register-handling",
    "ListCargos": "list-cargos",
}
def norm(text):
    text = re.sub(r"#[^\n]*", "", text)
    return re.sub(r"\s+", " ", text).strip()
source = open(ops_file).read()
starts = [(m.start(), m.group(2)) for m in re.finditer(r"^(query|mutation) (\w+)", source, re.M)]
bad = []
for i, (pos, name) in enumerate(starts):
    end = starts[i + 1][0] if i + 1 < len(starts) else len(source)
    # a comment that precedes the next operation belongs to it, and normalisation drops it
    mine = norm(source[pos:end])
    copy = norm(open("%s/%s.graphql" % (docs, files[name])).read())
    if mine != copy:
        bad.append(name)
if len(starts) != len(files):
    bad.append("operation count %d" % len(starts))
if bad:
    print("differs from Chapter 22: " + ", ".join(bad))
    sys.exit(1)
print("ok")
' "$CH22_OPERATIONS" "$DOCS"
}

# field_hits <coverage-json> <Type> <field> — how many documents select the field.
field_hits() {
  python3 -I -c '
import json, sys
report = json.load(open(sys.argv[1]))
print(report["types"][sys.argv[2]]["children"].get(sys.argv[3], {}).get("hits", 0))
' "$1" "$2" "$3"
}

# run_suite <service> <scratch-subdir> — run one test container with a mounted
# report directory; print the tail of its output when it fails.
run_suite() {
  local service="$1" dir="$SCRATCH/$2" out
  mkdir -m 0777 "$dir"
  if ! out="$(compose_run -v "$dir:/out:z" "$service" 2>&1)"; then
    echo "lib.sh: FAIL — $service exited non-zero:" >&2
    echo "$out" | tail -60 >&2
    return 1
  fi
  echo "lib.sh: ok — $service passed" >&2
}

# run_load <stack> <run> — one k6 run against the stack on the compose network;
# prints the JSON summary. A threshold that fails makes k6 exit non-zero.
run_load() {
  local stack="$1" run="$2" out
  if ! out="$(compose_run -e "TARGET=http://$stack:8080/graphql" -e "RUN=$run" -e "STACK=$stack" \
      load run --quiet /scripts/tracking.js 2>"$SCRATCH/k6.err")"; then
    echo "lib.sh: FAIL — k6 run '$run' on $stack exited non-zero:" >&2
    tail -30 "$SCRATCH/k6.err" >&2
    echo "$out" | tail -5 >&2
    return 1
  fi
  printf '%s\n' "$out" | tail -1
}

# expect_summary <summary> <iterations> <ctx> — the run did its iterations, and
# every check and the transport held.
expect_summary() {
  local summary="$1" iterations="$2" ctx="$3"
  assert_eq "$iterations" "$(json_field '.iterations' <<<"$summary")" "$ctx: iterations"
  assert_eq "1" "$(json_field '.checks.rate' <<<"$summary")" "$ctx: every check true"
  assert_eq "0" "$(json_field '.checks.fails' <<<"$summary")" "$ctx: no check failed"
  assert_eq "0" "$(json_field '.http_req_failed' <<<"$summary")" "$ctx: no transport failure"
  echo "lib.sh: info — $ctx: latency median $(json_field '.latency_ms.med' <<<"$summary") ms, p95 $(json_field '.latency_ms.p95' <<<"$summary") ms (reported, not asserted)" >&2
}

# request_shapes <calls-json> — "<count> <sorted entries>" per distinct set of
# calls that one request made, most frequent first.
request_shapes() {
  python3 -I -c '
import collections, json, sys
by_request = collections.defaultdict(list)
for c in json.load(sys.stdin)["calls"]:
    by_request[c["request"]].append("%s.%s:%s" % (c["source"], c["op"], c["key"]))
shapes = collections.Counter(",".join(sorted(v)) for v in by_request.values())
for shape, n in sorted(shapes.items(), key=lambda kv: (-kv[1], kv[0])):
    print(n, shape)
' <<<"$1"
}

# --- 1. documents (no server needed) -----------------------------------------

echo "=== Step 1: client documents ==="
ensure_contracts_tools

why="$(same_operations)" || { echo "lib.sh: FAIL — documents/ against Chapter 22: $why" >&2; exit 1; }
echo "lib.sh: ok — documents/ holds Chapter 22's four operations, text for text" >&2
if ! cmp -s "$CH22_FIXTURE" "$DOCS/fixtures/cargo-weight.graphql"; then
  echo "lib.sh: FAIL — documents/fixtures/cargo-weight.graphql differs from Chapter 22's fixture" >&2
  exit 1
fi
echo "lib.sh: ok — the cargo-weight fixture is Chapter 22's, byte for byte" >&2

rc=0
out="$(documents_validate "$DOCS/*.graphql")" || rc=$?
assert_eq "0" "$rc" "documents/*.graphql validate against the contract"
rc=0
out="$(documents_validate "$DOCS/load/*.graphql")" || rc=$?
assert_eq "0" "$rc" "documents/load/*.graphql validate against the contract"
rc=0
out="$(documents_validate "$DOCS/fixtures/cargo-weight.graphql")" || rc=$?
assert_eq "1" "$rc" "the cargo-weight document is refused by validation"
assert_contains "Cannot query field weight on type Cargo" "$out" "the validation message names Cargo.weight"

# Coverage: which fields of the contract the four client documents select.
coverage_json="$SCRATCH/coverage.json"
"$CONTRACTS_DIR/node_modules/.bin/graphql-inspector" coverage \
  "$DOCS/{track-cargo,track-cargo-brief,register-handling,list-cargos}.graphql" "$CANONICAL_SDL_GLOB" \
  --silent --write "$coverage_json" >/dev/null
assert_eq "2" "$(field_hits "$coverage_json" Query cargo)" "coverage: Query.cargo is selected by two documents"
assert_eq "1" "$(field_hits "$coverage_json" Query cargos)" "coverage: Query.cargos is selected by one document"
assert_eq "0" "$(field_hits "$coverage_json" Query voyage)" "coverage: Query.voyage is selected by none"

# --- 2. servers ----------------------------------------------------------------

echo
echo "=== Step 2: docker compose up ==="
compose_up "$COMPOSE_FILE" "$PROJECT"

# --- 3. the in-process suites ------------------------------------------------------

echo
echo "=== Step 3: the in-process suites ==="
run_suite quarkus-test qt
assert_junit "$SCRATCH/qt/surefire-reports" "$QUARKUS_TESTS" "Quarkus suite"
run_suite python-test pt
assert_junit "$SCRATCH/pt/junit.xml" "$PYTHON_TESTS" "Python suite"

# The schema each suite exported is checked against the contract: the claim is
# conformance, so the two exports are not compared with each other.
assert_sdl_conforms "$SCRATCH/qt/schema.graphql" "Quarkus suite's exported schema vs contracts/schema"
assert_sdl_conforms "$SCRATCH/pt/schema.graphql" "Python suite's exported schema vs contracts/schema"

# --- 4. each live stack --------------------------------------------------------------

# expect <expected> <json-path> <context> — assert one value of $resp.
expect() {
  assert_eq "$1" "$(json_field "$2" <<<"$resp")" "$stack $3"
}

# run_stack_check <stack> <host-url>
run_stack_check() {
  local stack="$1" url="$2" resp calls summary per_request fan_keys

  echo
  echo "=== verifying stack '$stack' at $url ==="

  wait_for_graphql "$url"

  case "$stack" in
    quarkus)
      per_request=8
      fan_keys='booking.listCargos:*,booking.getCargos:DEF456+STU678+VWX901+XYZ789,routing.getItineraries:DEF456+STU678+VWX901+XYZ789,routing.getItineraries:DEF456+STU678+VWX901+XYZ789,handling.listEventsFor:DEF456+STU678+VWX901+XYZ789,location.getLocations:DEHAM+SGSIN+USNYC,voyage.getVoyages:V100S+V200E+V300A,location.getLocations:CNSHA+DEHAM+NLRTM'
      ;;
    python)
      per_request=6
      fan_keys='booking.listCargos:*,booking.getCargos:DEF456+STU678+VWX901+XYZ789,routing.getItineraries:DEF456+STU678+VWX901+XYZ789,handling.listEventsFor:DEF456+STU678+VWX901+XYZ789,location.getLocations:CNSHA+DEHAM+NLRTM+SGSIN+USNYC,voyage.getVoyages:V100S+V200E+V300A'
      ;;
  esac

  # 1. The anchors: one FanOut, one over-budget document, one page over the cap.
  source_calls_reset "$url"
  resp="$(gql "$url" "$(<"$DOCS/fan-out.graphql")")"
  assert_no_errors "$resp" "$stack FanOut"
  assert_json_eq '["VWX901","XYZ789","STU678","DEF456"]' \
    "$(python3 -I -c 'import json, sys; print(json.dumps([e["node"]["trackingId"] for e in json.load(sys.stdin)["data"]["cargos"]["edges"]]))' <<<"$resp")" \
    "$stack FanOut pages the four cargos"
  assert_source_calls_exactly "$(source_calls "$url")" "$fan_keys" "$stack FanOut: $per_request source calls"

  source_calls_reset "$url"
  resp="$(gql "$url" "$(<"$DOCS/load/over-budget.graphql")")"
  assert_has_errors "$resp" "$stack OverBudget"
  assert_no_data "$resp" "$stack OverBudget: no data"
  expect "maximum query complexity exceeded 7651 > 1000" '.errors.0.message' "OverBudget: message"
  assert_source_call_count "$(source_calls "$url")" '*' '*' 0 "$stack OverBudget: refused before any source call"

  resp="$(gql "$url" '{ cargos(first: 51) { edges { node { trackingId } } } }')"
  assert_error_extension "$resp" '["cargos"]' code '"BAD_USER_INPUT"' "$stack first: 51: code"

  # 2. The load runs, in this order. Every run starts from an empty log and reads
  #    it once at the end; the one write (retry) comes before the read that depends on it.

  # fanout: 160 FanOut requests from 8 virtual users. Every request makes the
  # calls of a single request, and no key of another request enters its batches.
  source_calls_reset "$url"
  summary="$(run_load "$stack" fanout)"
  expect_summary "$summary" 160 "$stack load fanout"
  calls="$(source_calls "$url")"
  assert_request_count "$calls" 160 "$stack fanout: one request id per request"
  assert_calls_per_request "$calls" "$per_request" "$stack fanout: $per_request calls per request under concurrency"
  assert_calls_same_per_request "$calls" "$fan_keys" "$stack fanout: every request made Chapter 14's calls"

  # cost: 80 FanOut and 80 OverBudget at the same time. A refused request makes
  # no call, so 80 request ids appear in the log, each with the per-request calls.
  source_calls_reset "$url"
  summary="$(run_load "$stack" cost)"
  expect_summary "$summary" 160 "$stack load cost"
  calls="$(source_calls "$url")"
  assert_request_count "$calls" 80 "$stack cost: only the accepted requests reached a source"
  assert_calls_per_request "$calls" "$per_request" "$stack cost: $per_request calls per accepted request"
  assert_calls_same_per_request "$calls" "$fan_keys" "$stack cost: the accepted requests made their own calls"

  # retry: 40 concurrent registrations with one idempotency key write one event.
  source_calls_reset "$url"
  summary="$(run_load "$stack" retry)"
  expect_summary "$summary" 40 "$stack load retry"
  calls="$(source_calls "$url")"
  assert_source_call_count "$calls" handling appendEvent 1 "$stack retry: one write for 40 retries"
  assert_source_call_keys "$calls" handling appendEvent evt_10 "$stack retry: the event is evt_10"
  resp="$(gql "$url" "$(<"$DOCS/track-cargo-brief.graphql")" '{"id":"ABC123"}')"
  assert_no_errors "$resp" "$stack TrackCargoBrief after the retries"
  expect "IN_PORT" '.data.cargo.delivery.transportStatus' "ABC123 is IN_PORT after the registration"

  # mix: 120 requests over three documents. Each request makes the calls of its
  # document and no other: 80 cargo reads and 40 pages.
  source_calls_reset "$url"
  summary="$(run_load "$stack" mix)"
  expect_summary "$summary" 120 "$stack load mix"
  calls="$(source_calls "$url")"
  assert_request_count "$calls" 120 "$stack mix: one request id per request"
  assert_eq "80 booking.getCargo:ABC123,handling.listEventsFor:ABC123,routing.getItineraries:ABC123
40 booking.getCargos:ABC123+DEF456+GHI345+STU678+VWX901+XYZ789,booking.listCargos:*" \
    "$(request_shapes "$calls")" "$stack mix: two shapes of request, 80 and 40"

  # 3. The live schema: the load runs change no field, argument or nullability.
  assert_deprecated "$url" Itinerary finalArrivalDate "Use \`finalArrivalTime\`." "$stack Itinerary.finalArrivalDate"
  assert_not_deprecated "$url" Itinerary finalArrivalTime "$stack Itinerary.finalArrivalTime"
  local scalar
  for scalar in TrackingId UnLocode DateTime; do
    # shellcheck disable=SC2016  # GraphQL variables, not shell expansions
    resp="$(gql "$url" 'query Kind($n: String!) { __type(name: $n) { kind specifiedByURL } }' "{\"n\":\"$scalar\"}")"
    assert_no_errors "$resp" "$stack $scalar introspection"
    expect "SCALAR" '.data.__type.kind' "$scalar kind"
    case "$scalar" in
      UnLocode) expect "https://unece.org/trade/uncefact/unlocode" '.data.__type.specifiedByURL' "$scalar specifiedByURL" ;;
      DateTime) expect "https://www.rfc-editor.org/rfc/rfc3339" '.data.__type.specifiedByURL' "$scalar specifiedByURL" ;;
      *) assert_null_at "$resp" '.data.__type.specifiedByURL' "$stack $scalar has no specifiedByURL" ;;
    esac
  done
  assert_sdl_conforms "$url" "$stack schema vs contracts/schema"

  echo "=== $stack: test layers passed ==="
}

echo
echo "=== Step 4: the live stacks under load ==="
run_stack_check "quarkus" "http://localhost:8330/graphql"
run_stack_check "python" "http://localhost:8331/graphql"

echo
echo "PASS - Ch23 Testing GraphQL APIs: the Quarkus suite ($QUARKUS_TESTS tests) and the Python suite" \
     "($PYTHON_TESTS tests) pass in their test images and export schemas that conform to the canonical SDL;" \
     "Chapter 22's documents are the same text, validate against the contract, and the Cargo.weight" \
     "document is refused; and k6 runs them at volume on both stacks with every check true, the same" \
     "source calls for every request, every over-budget document refused with no call, and one write" \
     "for forty concurrent retries."
