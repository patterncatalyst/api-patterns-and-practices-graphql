#!/usr/bin/env bash
# examples/22-client-integration/verify.sh
#
# Ch22 Client integration: three typed clients run against both servers of the
# tracking view, which are unchanged from Chapter 13.
#   js-client      Apollo Client 4 with GraphQL Code Generator types. A normalized
#                  cache answers a second query with no request and takes the
#                  mutation payload into the cached cargo.
#   python-client  gql with the canonical SDL as its schema: documents are
#                  validated locally and a document the schema refuses is not sent.
#   java-client    SmallRye GraphQL typesafe client (ErrorOr for an edge that may
#                  fail, a mutation) and dynamic client (a document built at run time).
# Each client runs as a one-off container on the compose network against
# http://quarkus:8080/graphql and then http://python:8080/graphql. The JS client
# writes first (evt_10 for ABC123), then the Python client reads that state, then
# the Java client registers evt_11 for VWX901.
#
# The canonical schema reaches the client images through build.additional_contexts;
# contracts/schema/ is not copied into this example.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../_lib/lib.sh
source "$SCRIPT_DIR/../_lib/lib.sh"

PROJECT="gql-ch22-clients"
COMPOSE_FILE="$SCRIPT_DIR/compose.yaml"

# run_client <service> [args...] — run a client container and print the JSON
# lines it wrote. The image build logs share the stream, so only the lines that
# start with "{" are kept. Fails when the client exits non-zero.
run_client() {
  local out
  if ! out="$(compose_run "$@" 2>&1)"; then
    echo "lib.sh: FAIL — client '$1' exited non-zero:" >&2
    echo "$out" | tail -40 >&2
    return 1
  fi
  grep '^{' <<<"$out"
}

# step_of <lines> <step> — the JSON line whose "step" is the name.
step_of() {
  python3 -I -c '
import json, sys
for line in sys.stdin:
    if json.loads(line).get("step") == sys.argv[1]:
        print(line.strip())
        break
else:
    sys.exit("no step " + sys.argv[1])
' "$2" <<<"$1"
}

# field_of <step-line> <key> — one key of a step line.
field_of() {
  json_field ".$2" <<<"$1"
}

# expect_step <expected> <step-line> <key> <context>
expect_step() {
  assert_eq "$1" "$(field_of "$2" "$3")" "$stack $4"
}

# run_stack_check <stack> <host-url> <network-url>
run_stack_check() {
  local stack="$1" url="$2" internal="$3" resp calls lines line

  echo
  echo "=== verifying stack '$stack' at $url (clients use $internal) ==="

  wait_for_graphql "$url"

  # 1. Apollo Client: the normalized cache, then a response with errors. The first query is a request; the
  #    second selects a subset of the first on the same field and arguments and is
  #    answered from the cache; the cache holds one Cargo entry; the mutation
  #    payload updates that entry and a cache-only read shows the new status.
  source_calls_reset "$url"
  lines="$(run_client js-client "$internal")"
  line="$(step_of "$lines" track)"
  expect_step "ONBOARD_CARRIER" "$line" status "JS first query: status from the server"
  expect_step "1" "$line" fetches "JS first query: one request"
  line="$(step_of "$lines" brief)"
  expect_step "ONBOARD_CARRIER" "$line" status "JS subset query: status from the cache"
  expect_step "1" "$line" fetches "JS subset query: still one request"
  line="$(step_of "$lines" normalized)"
  assert_json_eq '["Cargo:cargo_ABC123"]' "$(field_of "$line" cargoKeys)" "$stack JS cache: one Cargo entry"
  assert_json_eq '["Location:loc_NLRTM","Location:loc_USNYC"]' "$(field_of "$line" locationKeys)" "$stack JS cache: Location entries keyed by id"
  line="$(step_of "$lines" after-mutation)"
  expect_step "evt_10" "$line" event "JS mutation: the unload is evt_10"
  expect_step "0" "$line" userErrors "JS mutation: no user errors"
  expect_step "IN_PORT" "$line" status "JS cache-only read sees the mutation payload"
  expect_step "2" "$line" fetches "JS run: two requests in all"
  # A response with data and errors: errorPolicy "all" resolves with both.
  line="$(step_of "$lines" partial)"
  expect_step "6" "$line" edges "JS partial result: six edges"
  expect_step "CombinedGraphQLErrors" "$line" error "JS partial result: the error object"
  case "$stack" in
    quarkus)
      expect_step "6" "$line" nullNodes "JS partial result: null nodes"
      expect_step "6" "$line" errors "JS partial result: errors"
      ;;
    python)
      expect_step "1" "$line" nullNodes "JS partial result: null nodes"
      expect_step "1" "$line" errors "JS partial result: errors"
      ;;
  esac
  expect_step "3" "$line" fetches "JS run: three requests in all"
  # The server saw one request for the first query, one for the mutation and one
  # for the page; the subset query made none. The mutation is one appendEvent.
  calls="$(source_calls "$url")"
  assert_request_count "$calls" 3 "$stack JS run: the server saw three requests"
  assert_source_call_count "$calls" handling appendEvent 1 "$stack JS run: one handling.appendEvent"

  # 2. gql: validation against the canonical SDL happens in the client.
  source_calls_reset "$url"
  lines="$(run_client python-client "$internal")"
  line="$(step_of "$lines" track)"
  expect_step "ABC123" "$line" trackingId "Python TrackCargo trackingId"
  expect_step "Palletized electronics" "$line" description "Python TrackCargo description"
  expect_step "IN_PORT" "$line" status "Python TrackCargo reads the state the JS client wrote"
  line="$(step_of "$lines" dsl)"
  expect_step "Rotterdam" "$line" location "Python DSL query: location name"
  line="$(step_of "$lines" local-validation)"
  expect_step "Cannot query field 'weight' on type 'Cargo'." "$line" error "Python local validation refuses the document"
  expect_step "0" "$line" sent "Python local validation: nothing is sent"
  line="$(step_of "$lines" partial)"
  expect_step "6" "$line" edges "Python partial result: six edges"
  assert_json_eq '["SERVICE_UNAVAILABLE"]' "$(field_of "$line" codes)" "$stack Python partial result: the error code"
  case "$stack" in
    quarkus)
      # SmallRye fails the batch of cargo loads as a whole: every edge carries the error.
      expect_step "6" "$line" nullNodes "Python partial result: null nodes"
      expect_step "6" "$line" errors "Python partial result: errors"
      ;;
    python)
      expect_step "1" "$line" nullNodes "Python partial result: null nodes"
      expect_step "1" "$line" errors "Python partial result: errors"
      assert_json_eq '[["cargos","edges",5,"node"]]' "$(field_of "$line" paths)" "$stack Python partial result: the failed edge is GHI345's"
      ;;
  esac
  line="$(step_of "$lines" summary)"
  expect_step "3" "$line" requests "Python client: three requests left the client"
  assert_request_count "$(source_calls "$url")" 3 "$stack Python client: the server saw the same three requests"

  # 3. SmallRye typesafe and dynamic clients.
  source_calls_reset "$url"
  lines="$(run_client -e "TRACKING_URL=$internal" java-client)"
  line="$(step_of "$lines" typesafe-cargo)"
  expect_step "ABC123" "$line" trackingId "Java typesafe cargo trackingId"
  expect_step "Palletized electronics" "$line" description "Java typesafe cargo description"
  expect_step "IN_PORT" "$line" status "Java typesafe cargo status"
  line="$(step_of "$lines" typesafe-page)"
  expect_step "6" "$line" edges "Java ErrorOr page: six edges"
  assert_json_eq '["booking service unavailable"]' "$(field_of "$line" messages)" "$stack Java ErrorOr page: the edge error message"
  case "$stack" in
    quarkus)
      expect_step "0" "$line" present "Java ErrorOr page: nodes present"
      expect_step "6" "$line" errors "Java ErrorOr page: edges with errors"
      assert_json_eq '[0,1,2,3,4,5]' "$(field_of "$line" failedEdges)" "$stack Java ErrorOr page: every edge of the batch failed"
      assert_json_eq '[]' "$(field_of "$line" presentIds)" "$stack Java ErrorOr page: no node present"
      ;;
    python)
      expect_step "5" "$line" present "Java ErrorOr page: nodes present"
      expect_step "1" "$line" errors "Java ErrorOr page: edges with errors"
      assert_json_eq '[5]' "$(field_of "$line" failedEdges)" "$stack Java ErrorOr page: the failed edge is GHI345's"
      assert_json_eq '["ABC123","DEF456","STU678","VWX901","XYZ789"]' "$(field_of "$line" presentIds)" "$stack Java ErrorOr page: every cargo but GHI345 is present"
      ;;
  esac
  line="$(step_of "$lines" typesafe-mutation)"
  expect_step "evt_11" "$line" event "Java typesafe mutation: the receive is evt_11"
  expect_step "IN_PORT" "$line" status "Java typesafe mutation: the payload's delivery"
  expect_step "0" "$line" userErrors "Java typesafe mutation: no user errors"
  line="$(step_of "$lines" dynamic-location)"
  expect_step "Rotterdam" "$line" name "Java dynamic client: location name"
  assert_source_call_count "$(source_calls "$url")" handling appendEvent 1 "$stack Java run: one handling.appendEvent"

  # 4. The deprecation of Chapter 11, the custom scalars, and the live schema: a
  #    client changes nothing on the server.
  assert_deprecated "$url" Itinerary finalArrivalDate "Use \`finalArrivalTime\`." "$stack Itinerary.finalArrivalDate"
  assert_not_deprecated "$url" Itinerary finalArrivalTime "$stack Itinerary.finalArrivalTime"
  local scalar
  for scalar in TrackingId UnLocode DateTime; do
    # shellcheck disable=SC2016  # GraphQL variables, not shell expansions
    resp="$(gql "$url" 'query Kind($n: String!) { __type(name: $n) { kind specifiedByURL } }' "{\"n\":\"$scalar\"}")"
    assert_no_errors "$resp" "$stack $scalar introspection"
    assert_eq "SCALAR" "$(json_field '.data.__type.kind' <<<"$resp")" "$stack $scalar kind"
    case "$scalar" in
      UnLocode) assert_eq "https://unece.org/trade/uncefact/unlocode" "$(json_field '.data.__type.specifiedByURL' <<<"$resp")" "$stack $scalar specifiedByURL" ;;
      DateTime) assert_eq "https://www.rfc-editor.org/rfc/rfc3339" "$(json_field '.data.__type.specifiedByURL' <<<"$resp")" "$stack $scalar specifiedByURL" ;;
      *) assert_null_at "$resp" '.data.__type.specifiedByURL' "$stack $scalar has no specifiedByURL" ;;
    esac
  done
  assert_sdl_conforms "$url" "$stack schema vs contracts/schema"
  # Only Subscription is unserved: the canonical -> live breaking lines, less the
  # framework noise, are exactly its two removals.
  local sdl_rev sdl_removed
  sdl_rev="$(_sdl_diff "$CANONICAL_SDL_GLOB" "$url")"
  sdl_removed="$(grep '✖' <<<"$sdl_rev" | grep -vE "$LGTM_SDL_IGNORE" | sed -E 's/^.*✖ +//' | sort || true)"
  assert_eq "Schema subscription type Subscription was removed.
Type Subscription was removed" "$sdl_removed" "$stack only Subscription is unserved"

  echo "=== $stack: client check passed ==="
}

echo "=== Step 1: docker compose up ==="
compose_up "$COMPOSE_FILE" "$PROJECT"

echo
echo "=== Step 2: code generation refuses a document the contract does not support ==="
# codegen-check runs the build stage of the JS image against a document that
# selects Cargo.weight. The image build of js-client has already generated types
# from the documents and type-checked main.ts against them.
if out="$(compose_run codegen-check 2>&1)"; then
  echo "lib.sh: FAIL — codegen accepted a document that selects Cargo.weight" >&2
  exit 1
fi
assert_contains 'Cannot query field "weight" on type "Cargo"' "$out" "codegen names the field the schema lacks"
assert_contains "no files were generated" "$out" "codegen writes nothing for the refused document"

echo
echo "=== Step 3: run the clients against both stacks ==="
run_stack_check "quarkus" "http://localhost:8320/graphql" "http://quarkus:8080/graphql"
run_stack_check "python" "http://localhost:8321/graphql" "http://python:8080/graphql"

echo
echo "PASS - Ch22 Client integration: Apollo Client's normalized cache answers a subset query with no" \
     "request and takes the mutation payload into the cached cargo, GraphQL Code Generator refuses a" \
     "document the contract lacks, gql validates documents against the canonical SDL and sends nothing" \
     "for a refused one, SmallRye's typesafe client reports the failed edge through ErrorOr and its" \
     "dynamic client builds a document at run time, all against both stacks, and both schemas still" \
     "conform to the canonical SDL except for Subscription."
