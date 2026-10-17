#!/usr/bin/env bash
# examples/00-prerequisites/verify.sh
#
# Ch0 prerequisites SKELETON - proves the toolchain, not the domain: both the
# Quarkus (SmallRye GraphQL) and the Python (Strawberry) stack build their
# schema code-first, boot under Compose, answer Query.cargo with the canned
# cargo ABC123, and expose a schema that conforms to the canonical SDL in
# contracts/schema/. Nothing is computed or persisted; the deeper schema and
# resolver checks start in later chapters.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../_lib/lib.sh
source "$SCRIPT_DIR/../_lib/lib.sh"

PROJECT="gql-ch00-prereq"
COMPOSE_FILE="$SCRIPT_DIR/compose.yaml"

# shellcheck disable=SC2016  # GraphQL variables, not shell expansions
CARGO_QUERY='query Cargo($t: TrackingId!) {
  cargo(trackingId: $t) {
    __typename
    id
    trackingId
    description
    origin { __typename id unLocode name country }
    destination { unLocode name }
  }
}'

run_stack_check() {
  local stack="$1" url="$2"

  echo
  echo "=== verifying stack '$stack' at $url ==="

  wait_for_graphql "$url"

  # 1. The canned cargo: every selected field has its exact canned value.
  local resp
  resp="$(gql "$url" "$CARGO_QUERY" '{"t":"ABC123"}')"
  assert_no_errors "$resp" "$stack cargo(ABC123)"
  assert_eq "Cargo" "$(json_field '.data.cargo.__typename' <<<"$resp")" "$stack cargo.__typename"
  assert_eq "cargo_ABC123" "$(json_field '.data.cargo.id' <<<"$resp")" "$stack cargo.id"
  assert_eq "ABC123" "$(json_field '.data.cargo.trackingId' <<<"$resp")" "$stack cargo.trackingId"
  assert_eq "Palletized electronics" "$(json_field '.data.cargo.description' <<<"$resp")" "$stack cargo.description"
  assert_eq "Location" "$(json_field '.data.cargo.origin.__typename' <<<"$resp")" "$stack cargo.origin.__typename"
  assert_eq "loc_USNYC" "$(json_field '.data.cargo.origin.id' <<<"$resp")" "$stack cargo.origin.id"
  assert_eq "USNYC" "$(json_field '.data.cargo.origin.unLocode' <<<"$resp")" "$stack cargo.origin.unLocode"
  assert_eq "New York" "$(json_field '.data.cargo.origin.name' <<<"$resp")" "$stack cargo.origin.name"
  assert_eq "US" "$(json_field '.data.cargo.origin.country' <<<"$resp")" "$stack cargo.origin.country"
  assert_eq "NLRTM" "$(json_field '.data.cargo.destination.unLocode' <<<"$resp")" "$stack cargo.destination.unLocode"
  assert_eq "Rotterdam" "$(json_field '.data.cargo.destination.name' <<<"$resp")" "$stack cargo.destination.name"

  # 2. An unknown tracking id is data, not an error: Query.cargo is nullable.
  resp="$(gql "$url" "$CARGO_QUERY" '{"t":"NOPE99"}')"
  assert_no_errors "$resp" "$stack cargo(NOPE99)"
  assert_null_at "$resp" '.data.cargo' "$stack unknown cargo is null"

  # 3. A missing non-null argument is rejected at validation: HTTP 200 with
  #    top-level errors and no data.
  resp="$(gql "$url" 'query { cargo { trackingId } }')"
  assert_has_errors "$resp" "$stack cargo without trackingId"
  assert_contains "trackingId" "$(json_field '.errors.0.message' <<<"$resp")" \
    "$stack missing-argument error names trackingId"
  if json_field '.data' <<<"$resp" >/dev/null 2>&1 \
     && [[ "$(json_field '.data' <<<"$resp")" != "null" ]]; then
    echo "lib.sh: FAIL — $stack: validation failure must not return data: $resp" >&2
    return 1
  fi

  # 3b. TrackingId is a string scalar: a number for it is rejected, not coerced.
  resp="$(gql "$url" "$CARGO_QUERY" '{"t":123}')"
  assert_has_errors "$resp" "$stack TrackingId given a number"
  if json_field '.data' <<<"$resp" >/dev/null 2>&1 \
     && [[ "$(json_field '.data' <<<"$resp")" != "null" ]]; then
    echo "lib.sh: FAIL — $stack: an invalid variable must not return data: $resp" >&2
    return 1
  fi

  # 4. The custom scalars have kind SCALAR in the live schema, not strings,
  #    and carry the canonical @specifiedBy URL (UnLocode) or none
  #    (TrackingId). The live schema is the source for specifiedByURL,
  #    and this loop reads it from introspection. (One
  #    __type per operation: graphql-java's introspection guard accepts one
  #    `__type` field per request.)
  local scalar specified_by
  for scalar in TrackingId UnLocode; do
    case "$scalar" in
      UnLocode) specified_by="https://unece.org/trade/uncefact/unlocode" ;;
      *) specified_by="null" ;;
    esac
    # shellcheck disable=SC2016
    resp="$(gql "$url" 'query Kind($n: String!) { __type(name: $n) { kind specifiedByURL } }' "{\"n\":\"$scalar\"}")"
    assert_no_errors "$resp" "$stack $scalar introspection"
    assert_eq "SCALAR" "$(json_field '.data.__type.kind' <<<"$resp")" "$stack $scalar kind"
    if [[ "$specified_by" == "null" ]]; then
      assert_null_at "$resp" '.data.__type.specifiedByURL' "$stack $scalar has no specifiedByURL"
    else
      assert_eq "$specified_by" "$(json_field '.data.__type.specifiedByURL' <<<"$resp")" \
        "$stack $scalar specifiedByURL"
    fi
  done

  # 5. The live schema conforms to the canonical SDL (slice).
  assert_sdl_conforms "$url" "$stack schema vs contracts/schema"

  echo "=== $stack: toolchain check passed ==="
}

echo "=== Step 1: docker compose up ==="
compose_up "$COMPOSE_FILE" "$PROJECT"

echo
echo "=== Step 2: verify both stacks ==="
run_stack_check "quarkus" "http://localhost:8080/graphql"
run_stack_check "python" "http://localhost:8081/graphql"

echo
echo "PASS - Ch0 prerequisites skeleton: Quarkus (SmallRye GraphQL) and Python" \
     "(Strawberry) both build code-first, boot under Compose, return the canned" \
     "cargo ABC123 from Query.cargo with exact field values, and expose a schema" \
     "that conforms to the canonical SDL - the toolchain works."

# Explicit teardown in addition to lib.sh's EXIT trap (belt-and-suspenders);
# compose_down is idempotent/safe to call twice.
compose_down "$COMPOSE_FILE" "$PROJECT"
