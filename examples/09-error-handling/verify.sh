#!/usr/bin/env bash
# examples/09-error-handling/verify.sh
#
# Ch9 Error handling: exposed and masked execution errors, partial data, error
# paths, the extensions.code vocabulary, request-error shape, status codes by
# media type, and errors as data (userErrors), on both stacks.
#
# The fault seeds do the failing. JKL567 sails on V404X, whose voyage source
# raises an exposed SourceUnavailable (code SERVICE_UNAVAILABLE). PQR234's
# handling source raises an unexpected error that carries a shard name, which
# must reach the server log and no client. MNO901 loads at XXBAD, which the
# location source answers with null where the schema says non-null.
#
# Two things differ per stack, and are passed in rather than hidden:
#   - the extensions.code of a masked exception (see the README's code-first notes): Quarkus
#     sends "code": null (DeclaredErrorCodeProvider declares no code for it),
#     Strawberry sends no extensions at all;
#   - a null in a non-null field (see the README): SmallRye shows graphql-java's own
#     text, with no locations and the classification NullValueInNonNullableField;
#     Strawberry masks it.
# And so does the Content-Type of a response to Accept:
# application/graphql-response+json: Quarkus echoes it, Strawberry answers
# application/json.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../_lib/lib.sh
source "$SCRIPT_DIR/../_lib/lib.sh"

PROJECT="gql-ch09-errors"
COMPOSE_FILE="$SCRIPT_DIR/compose.yaml"

# Case 1 and case 5 documents are reused by the status-code table (case 6).
EXPOSED_QUERY='{ cargo(trackingId: "JKL567") { trackingId itinerary { legs { loadLocation { unLocode } voyage { number } } } } }'
MASKED_QUERY='{ cargo(trackingId: "PQR234") { trackingId delivery { transportStatus } } }'
THREE_ALIASES='{ ok: cargo(trackingId: "ABC123") { trackingId } outage: cargo(trackingId: "JKL567") { itinerary { legs { voyage { number } } } } bug: cargo(trackingId: "PQR234") { delivery { transportStatus } } }'
NULL_IN_NON_NULL='{ cargo(trackingId: "MNO901") { trackingId itinerary { legs { loadLocation { unLocode } } } } }'
REQUEST_ERROR='{ cargo(trackingId: "ABC123") { weight } }'
SIBLINGS='{ a: voyage(voyageNumber: "V404X") { number } b: voyage(voyageNumber: "V100S") { number } }'
# shellcheck disable=SC2016  # a GraphQL variable, not a shell expansion
REGISTER='mutation($i: RegisterHandlingEventInput!) { registerHandlingEvent(input: $i) { handlingEvent { id } cargo { trackingId } userErrors { code message field } } }'

# expect <expected> <json-path> <context> — assert one value of $resp.
expect() {
  assert_eq "$1" "$(json_field "$2" <<<"$resp")" "$stack $3"
}

# run_stack_check <stack> <url> <masked code (JSON) or "-" for no extensions>
#   <null-in-non-null message: "contains:<text>" or "exact:<text>">
#   <media type for graphql-response+json> <classification of the null-in-non-null
#   error (JSON) or "-" for none>
run_stack_check() {
  local stack="$1" url="$2" masked_code="$3" null_message="$4" gr_type="$5" null_class="$6" resp calls out logs

  echo
  echo "=== verifying stack '$stack' at $url ==="

  wait_for_graphql "$url"

  # 1. An exposed execution error: the voyage service is down for V404X. One
  #    error, at the voyage, with the message and code the service chose; the
  #    rest of the response is intact.
  source_calls_reset "$url"
  resp="$(gql "$url" "$EXPOSED_QUERY")"
  assert_error_count "$resp" 1 "$stack exposed: one error"
  assert_error_path "$resp" '["cargo","itinerary","legs",0,"voyage"]' "$stack exposed: path"
  assert_error_message_at "$resp" '["cargo","itinerary","legs",0,"voyage"]' "voyage service unavailable" "$stack exposed: message"
  assert_error_extension "$resp" '["cargo","itinerary","legs",0,"voyage"]' code '"SERVICE_UNAVAILABLE"' "$stack exposed: code"
  assert_error_shape "$resp" execution "$stack exposed: execution error shape"
  assert_null_at "$resp" '.data.cargo.itinerary.legs.0.voyage' "$stack exposed: the voyage is the null hole"
  expect "USNYC" '.data.cargo.itinerary.legs.0.loadLocation.unLocode' "exposed: sibling field still resolved"
  expect "JKL567" '.data.cargo.trackingId' "exposed: cargo still resolved"
  echo "--- $stack exposed error: $(json_field '.errors.0' <<<"$resp") ---" >&2

  # 2. A masked execution error: an unexpected failure in the handling source.
  #    delivery is non-null, so the null climbs to cargo. The client reads a
  #    generic message and no internal detail; the detail is in the server log.
  resp="$(gql "$url" "$MASKED_QUERY")"
  assert_error_count "$resp" 1 "$stack masked: one error"
  assert_null_at "$resp" '.data.cargo' "$stack masked: delivery is non-null, so cargo is the hole"
  assert_error_path "$resp" '["cargo","delivery"]' "$stack masked: path"
  assert_error_message_at "$resp" '["cargo","delivery"]' "Internal server error." "$stack masked: message"
  assert_body_not_contains "$resp" "handling-primary-3" "$stack masked: no shard name"
  assert_body_not_contains "$resp" "IllegalStateException" "$stack masked: no Java exception name"
  assert_body_not_contains "$resp" "RuntimeError" "$stack masked: no Python exception name"
  assert_body_not_contains "$resp" "com.patterncatalyst" "$stack masked: no package name"
  if [[ "$masked_code" == "-" ]]; then
    assert_absent "$resp" '.errors.0.extensions' "$stack masked: no extensions"
  else
    # DeclaredErrorCodeProvider answers JSON null for an exception with no
    # @ErrorCode, and SmallRye's built-in providers are removed from the
    # build; asserted so an upgrade that changes it is noticed.
    assert_error_extension "$resp" '["cargo","delivery"]' code "$masked_code" "$stack masked: code is null"
  fi
  echo "--- $stack masked error: $(json_field '.errors.0' <<<"$resp") ---" >&2
  logs="$(compose_logs "$stack")"
  if [[ "$(grep -c 'handling-primary-3' <<<"$logs" || true)" -lt 1 ]]; then
    echo "FAIL ($stack): the server log lacks the detail 'handling-primary-3'" >&2
    return 1
  fi
  echo "--- $stack server log keeps the detail: $(grep -m1 'handling-primary-3' <<<"$logs" | cut -c1-200) ---" >&2

  # 3. Partial data: three aliases, one healthy, one exposed failure, one
  #    masked failure. Two errors, each path naming where it broke.
  resp="$(gql "$url" "$THREE_ALIASES")"
  assert_error_count "$resp" 2 "$stack partial: two errors"
  assert_error_path "$resp" '["outage","itinerary","legs",0,"voyage"]' "$stack partial: outage path"
  assert_error_path "$resp" '["bug","delivery"]' "$stack partial: bug path"
  expect "ABC123" '.data.ok.trackingId' "partial: the healthy alias is intact"
  assert_null_at "$resp" '.data.bug' "$stack partial: bug is null at the cargo"
  assert_null_at "$resp" '.data.outage.itinerary.legs.0.voyage' "$stack partial: outage is null at the voyage"
  assert_eq "ok,outage,bug" "$(json_keys .data <<<"$resp")" "$stack partial: data keys follow the selection"
  assert_error_shape "$resp" execution "$stack partial: execution error shape"

  # 4. Null propagation meets an error: loadLocation is non-null, the location
  #    source has no XXBAD, so the null climbs to itinerary (nullable).
  resp="$(gql "$url" "$NULL_IN_NON_NULL")"
  assert_error_count "$resp" 1 "$stack null in non-null: one error"
  assert_null_at "$resp" '.data.cargo.itinerary' "$stack null in non-null: the hole is the itinerary"
  assert_error_path "$resp" '["cargo","itinerary","legs",0,"loadLocation"]' "$stack null in non-null: path"
  expect "MNO901" '.data.cargo.trackingId' "null in non-null: cargo intact"
  case "$null_message" in
    contains:*) assert_error_message_contains "$resp" "${null_message#contains:}" "$stack null in non-null: engine message shown" ;;
    exact:*) assert_error_message_at "$resp" '["cargo","itinerary","legs",0,"loadLocation"]' "${null_message#exact:}" "$stack null in non-null: message masked" ;;
  esac
  if [[ "$null_class" != "-" ]]; then
    # graphql-java's own error: no locations, and its classification.
    assert_absent "$resp" '.errors.0.locations' "$stack null in non-null: no locations"
    assert_error_extension "$resp" '["cargo","itinerary","legs",0,"loadLocation"]' classification "$null_class" "$stack null in non-null: classification"
  fi

  # 5. A request error: the field does not exist. Errors with locations and no
  #    path, no data, and no resolver ran.
  source_calls_reset "$url"
  resp="$(gql "$url" "$REQUEST_ERROR")"
  assert_has_errors "$resp" "$stack request error"
  assert_no_data "$resp" "$stack request error has no data"
  assert_error_shape "$resp" request "$stack request error shape"
  assert_eq "0" "$(source_calls "$url" | json_len .calls)" "$stack request error calls no source"
  echo "--- $stack request error: $(json_field '.errors.0.message' <<<"$resp") ---" >&2

  # 6. Status codes and media types. The current GraphQL-over-HTTP working draft
  #    recommends a 4xx/5xx for a result with no data entry (a request error),
  #    for application/json too (a legacy Accept is handled as
  #    graphql-response+json), and 294 for data plus errors. Both stacks answer
  #    200 for the request error and for the execution error. The values are
  #    asserted so a change is noticed.
  out="$(gql_meta "$url" application/json "$REQUEST_ERROR")"
  assert_eq "200 application/json" "$out" "$stack request error, Accept json"
  out="$(gql_meta "$url" application/graphql-response+json "$REQUEST_ERROR")"
  assert_eq "200 $gr_type" "$out" "$stack request error, Accept graphql-response+json"
  out="$(gql_meta "$url" application/json "$EXPOSED_QUERY")"
  assert_eq "200 application/json" "$out" "$stack execution error, Accept json"
  out="$(gql_meta "$url" application/graphql-response+json "$EXPOSED_QUERY")"
  assert_eq "200 $gr_type" "$out" "$stack execution error, Accept graphql-response+json"
  echo "--- $stack graphql-response+json is answered as: $out ---" >&2

  # 7. Errors as data: a domain failure is payload userErrors, not errors[].
  source_calls_reset "$url"
  resp="$(gql "$url" "$REGISTER" '{"i":{"trackingId":"ABC123","type":"LOAD","location":"DEHAM","voyageNumber":"V999X","completionTime":"2026-10-09T15:00:00Z"}}')"
  assert_no_errors "$resp" "$stack userErrors: no errors[]"
  assert_json_eq '[{"code":"UNKNOWN_VOYAGE","field":["input","voyageNumber"]}]' \
    "$(python3 -I -c '
import json, sys
errors = json.load(sys.stdin)["data"]["registerHandlingEvent"]["userErrors"]
if any(not e["message"] for e in errors):
    sys.exit("empty userError message")
print(json.dumps([{"code": e["code"], "field": e["field"]} for e in errors]))
' <<<"$resp")" "$stack userErrors: code and field"
  assert_null_at "$resp" '.data.registerHandlingEvent.handlingEvent' "$stack userErrors: no event"
  assert_source_call_count "$(source_calls "$url")" handling appendEvent 0 "$stack userErrors: nothing written"
  echo "--- $stack userErrors: $(json_field '.data.registerHandlingEvent.userErrors' <<<"$resp") ---" >&2

  # 8. Masking leaves exposed errors alone, next to a healthy sibling.
  resp="$(gql "$url" "$SIBLINGS")"
  assert_error_count "$resp" 1 "$stack siblings: one error"
  assert_error_path "$resp" '["a"]' "$stack siblings: path"
  assert_error_extension "$resp" '["a"]' code '"SERVICE_UNAVAILABLE"' "$stack siblings: code"
  assert_error_message_at "$resp" '["a"]' "voyage service unavailable" "$stack siblings: message"
  assert_null_at "$resp" '.data.a' "$stack siblings: a is null"
  expect "V100S" '.data.b.number' "siblings: b resolved"

  # 9. The custom scalars, and the live schema against the canonical SDL (this
  #    chapter adds no schema).
  local scalar
  for scalar in TrackingId UnLocode DateTime; do
    # shellcheck disable=SC2016
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

  echo "=== $stack: error-handling check passed ==="
}

echo "=== Step 1: docker compose up ==="
compose_up "$COMPOSE_FILE" "$PROJECT"

echo
echo "=== Step 2: verify both stacks ==="
run_stack_check "quarkus" "http://localhost:8190/graphql" 'null' "contains:loadLocation" "application/graphql-response+json" '"NullValueInNonNullableField"'
run_stack_check "python" "http://localhost:8191/graphql" "-" "exact:Internal server error." "application/json" "-"

echo
echo "PASS - Ch9 Error handling: Quarkus (SmallRye GraphQL, allowlisted messages) and" \
     "Python (Strawberry, MaskErrors with an ExposedError allowlist) answer an outage with the" \
     "same message and code (SERVICE_UNAVAILABLE), mask an unexpected failure as" \
     "'Internal server error.' while the server log keeps the detail, return partial data with" \
     "error paths, answer 200 for request and execution errors under both media types (the GraphQL-over-HTTP draft recommends 4xx and 294)," \
     "keep domain failures in userErrors, and conform to the canonical SDL."
