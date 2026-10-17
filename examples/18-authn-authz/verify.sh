#!/usr/bin/env bash
# examples/18-authn-authz/verify.sh
#
# Ch18 AuthN and AuthZ: Keycloak issues the tokens, each stack validates them
# (Quarkus: quarkus-oidc; Python: PyJWT with PyJWKClient) and authorizes three
# ways:
#   operation  cargo and cargos need a signed-in caller; registerHandlingEvent needs
#              the operator role
#   object     a shipper sees only its own cargos, on every path to a cargo, because
#              the booking source is the one place the rule lives
#   field      HandlingEvent.registrationTime is for operators
# A request with no token is anonymous (public data still works). A token that
# does not validate is HTTP 401 with WWW-Authenticate before GraphQL runs.
#
# Users (test fixtures, keycloak/shipping-realm.json):
#   ana  shipper ACME    owns VWX901, DEF456, ABC123
#   bo   shipper GLOBEX  owns XYZ789, STU678, GHI345 (the booking outage seed)
#   ops  operator        sees every cargo and every field
#
# Tokens are fetched at http://localhost:8282, the address Keycloak is published
# on: the apps pin that address as the issuer.
#
# The cases run in a fixed order and handling state carries forward: case 8
# registers evt_10 for ABC123, so it runs after every read of ABC123's history.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../_lib/lib.sh
source "$SCRIPT_DIR/../_lib/lib.sh"

PROJECT="gql-ch18-authn-authz"
COMPOSE_FILE="$SCRIPT_DIR/compose.yaml"
REALM_URL="http://localhost:8282/realms/shipping"
TOKEN_URL="$REALM_URL/protocol/openid-connect/token"

# shellcheck disable=SC2016  # GraphQL variables, not shell expansions
REGISTER='mutation($i: RegisterHandlingEventInput!) { registerHandlingEvent(input: $i) { handlingEvent { id registrationTime } cargo { delivery { transportStatus } } userErrors { code } } }'
UNLOAD='{"i":{"trackingId":"ABC123","type":"UNLOAD","location":"DEHAM","voyageNumber":"V100S","completionTime":"2026-10-09T15:00:00Z"}}'
HISTORY='{ cargo(trackingId: "ABC123") { handlingHistory(first: 2) { edges { cursor node { id registrationTime } } } } }'

# as <token-or-empty> <gql args...> — one GraphQL request as that caller.
as() {
  local token="$1"
  shift
  LGTM_BEARER="$token" gql "$@"
}

# expect <expected> <json-path> <context> — assert one value of $resp.
expect() {
  assert_eq "$1" "$(json_field "$2" <<<"$resp")" "$stack $3"
}

# expect_json <expected-json> <json-path> <context>
expect_json() {
  assert_json_eq "$1" "$(json_field "$2" <<<"$resp")" "$stack $3"
}

# project <list-path> <field.path> — a JSON list: the dotted field of each item of
# the list at <list-path> in $resp (null where the path runs into a null).
project() {
  python3 -I -c '
import json, sys
value = json.load(sys.stdin)
for part in sys.argv[1].strip(".").split("."):
    value = value[int(part)] if part.isdigit() else value[part]
out = []
for item in value:
    for part in sys.argv[2].split("."):
        item = None if item is None else item[part]
    out.append(item)
print(json.dumps(out))
' "$1" "$2" <<<"$resp"
}

# expect_project <expected-json> <list-path> <field.path> <context>
expect_project() {
  assert_json_eq "$1" "$(project "$2" "$3")" "$stack $4"
}

# tamper <token> signature|payload — a token that no longer matches its signature.
# signature: one character in the middle of the signature changes, so the signature
# bytes change.
# payload: the realm role is rewritten to operator and the signature is kept.
tamper() {
  python3 -I -c '
import base64, json, sys
head, payload, sig = sys.argv[1].split(".")
if sys.argv[2] == "signature":
    sig = sig[:10] + ("B" if sig[10] != "B" else "C") + sig[11:]
else:
    claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
    claims["realm_access"] = {"roles": ["operator"]}
    payload = base64.urlsafe_b64encode(json.dumps(claims).encode()).rstrip(b"=").decode()
print(".".join([head, payload, sig]))
' "$1" "$2"
}

# assert_rejected <stack> <url> <token> <context> — HTTP 401 with the stack's exact
# challenge and body, whatever the operation (here a public one).
#   quarkus  WWW-Authenticate: Bearer                         empty body
#   python   WWW-Authenticate: Bearer error="invalid_token"   {"detail":"invalid token"}
assert_rejected() {
  local stack="$1" url="$2" token="$3" context="$4" out headers want_header want_body
  case "$stack" in
    python)
      want_header='Bearer error="invalid_token"'
      want_body='{"detail":"invalid token"}'
      ;;
    quarkus)
      want_header='Bearer'
      want_body=''
      ;;
  esac
  out="$(LGTM_BEARER="$token" gql_any "$url" '{ location(unLocode: "NLRTM") { name } }')"
  assert_status_in "401" "$(status_of "$out")" "$context: status" || return 1
  assert_body_not_contains "$(body_of "$out")" '"data"' "$context: no GraphQL body" || return 1
  assert_eq "$want_body" "$(body_of "$out")" "$context: exact 401 body" || return 1
  headers="$(LGTM_BEARER="$token" http_headers POST "$url" -H 'Content-Type: application/json' -d '{"query":"{ __typename }"}')"
  assert_eq "$want_header" "$(header_value "$headers" www-authenticate)" "$context: exact WWW-Authenticate" || return 1
}

# run_stack_check <stack> <url>
run_stack_check() {
  local stack="$1" url="$2" resp calls out headers

  echo
  echo "=== verifying stack '$stack' at $url ==="

  wait_for_graphql "$url"

  # 1. Public data needs no token.
  resp="$(gql "$url" '{ location(unLocode: "NLRTM") { name } }')"
  assert_no_errors "$resp" "$stack anonymous location"
  expect "Rotterdam" '.data.location.name' "anonymous caller reads public reference data"

  # 2. An anonymous caller reaching an authenticated operation: UNAUTHENTICATED,
  #    and no source is asked. cargo is nullable, so only the field is null;
  #    cargos is non-null, so the null climbs to data.
  source_calls_reset "$url"
  resp="$(gql "$url" '{ cargo(trackingId: "ABC123") { trackingId } }')"
  assert_null_at "$resp" '.data.cargo' "$stack anonymous cargo is null"
  assert_error_count "$resp" 1 "$stack anonymous cargo: one error"
  assert_error_path "$resp" '["cargo"]' "$stack anonymous cargo: error path"
  assert_error_extension "$resp" '["cargo"]' code '"UNAUTHENTICATED"' "$stack anonymous cargo: code"
  assert_error_message_at "$resp" '["cargo"]' "authentication required" "$stack anonymous cargo: message"
  assert_error_shape "$resp" execution "$stack anonymous cargo: execution error shape"
  resp="$(gql "$url" '{ cargos(first: 2) { totalCount } }')"
  assert_null_at "$resp" '.data' "$stack anonymous cargos nulls data (the connection is non-null)"
  assert_error_extension "$resp" '["cargos"]' code '"UNAUTHENTICATED"' "$stack anonymous cargos: code"
  assert_body_not_contains "$resp" 'io.quarkus' "$stack no framework class name reaches the client"
  assert_body_not_contains "$resp" 'Exception' "$stack no exception name reaches the client"
  assert_source_call_count "$(source_calls "$url")" '*' '*' 0 "$stack refused operations make no source call"

  # 3. node and nodes stay open: what the caller may not see is null.
  resp="$(gql "$url" '{ nodes(ids: ["loc_NLRTM", "cargo_ABC123"]) { __typename } }')"
  assert_no_errors "$resp" "$stack anonymous nodes"
  expect_json '[{"__typename":"Location"},null]' '.data.nodes' "anonymous nodes: the location, and null for the cargo"
  resp="$(gql "$url" '{ a: node(id: "cargo_ABC123") { id } b: node(id: "evt_1") { id } }')"
  assert_no_errors "$resp" "$stack anonymous node"
  expect_json '{"a":null,"b":null}' '.data' "anonymous node: cargo and event are null"

  # 4. ana (ACME): her three cargos, counted by totalCount, and nothing of GLOBEX's.
  resp="$(as "$ANA" "$url" '{ cargos(first: 10) { edges { node { trackingId } } totalCount } }')"
  assert_no_errors "$resp" "$stack ana cargos"
  expect_project '["VWX901","DEF456","ABC123"]' .data.cargos.edges node.trackingId "ana sees her three cargos, newest first"
  expect "3" '.data.cargos.totalCount' "ana's totalCount counts only her cargos"
  resp="$(as "$ANA" "$url" '{ cargos(first: 10, routingStatus: NOT_ROUTED) { edges { node { trackingId } } totalCount } }')"
  assert_no_errors "$resp" "$stack ana filtered cargos"
  expect "0" '.data.cargos.totalCount' "ana: the filter composes with ownership (both NOT_ROUTED cargos are GLOBEX's)"
  expect_json '[]' '.data.cargos.edges' "ana: no edges"
  resp="$(as "$ANA" "$url" '{ cargo(trackingId: "XYZ789") { trackingId } }')"
  assert_no_errors "$resp" "$stack ana asks for a GLOBEX cargo"
  assert_null_at "$resp" '.data.cargo' "$stack a cargo owned by another shipper is null"
  assert_json_eq "$resp" "$(as "$ANA" "$url" '{ cargo(trackingId: "ZZZ999") { trackingId } }')" "$stack not owned and unknown are the same answer"
  resp="$(as "$ANA" "$url" '{ cargo(trackingId: "GHI345") { trackingId } }')"
  assert_no_errors "$resp" "$stack ana asks for GHI345"
  assert_null_at "$resp" '.data.cargo' "$stack GHI345 is null for ana: its outage is bo's to see"
  resp="$(as "$ANA" "$url" '{ a: node(id: "cargo_XYZ789") { id } b: node(id: "evt_1") { id } }')"
  assert_no_errors "$resp" "$stack ana node"
  expect_json '{"a":null,"b":{"id":"evt_1"}}' '.data' "ana: another shipper's cargo is null, her own event resolves"
  # HandlingEvent.cargo reads the booking source as the caller. (Every seeded
  # event belongs to an ACME cargo, so there is no event of bo's to reach it
  # from; bo's null for evt_1 is asserted in case 5.)
  resp="$(as "$ANA" "$url" '{ node(id: "evt_1") { ... on HandlingEvent { cargo { trackingId } } } }')"
  assert_no_errors "$resp" "$stack ana HandlingEvent.cargo"
  expect "ABC123" '.data.node.cargo.trackingId' "HandlingEvent.cargo reads the booking source as the caller"

  # 5. bo (GLOBEX): the same data from the other side, through every path.
  resp="$(as "$BO" "$url" '{ cargos(first: 2) { edges { node { trackingId } } totalCount pageInfo { hasNextPage } } }')"
  assert_no_errors "$resp" "$stack bo first page"
  expect_project '["XYZ789","STU678"]' .data.cargos.edges node.trackingId "bo sees her cargos, newest first"
  expect "3" '.data.cargos.totalCount' "bo's totalCount"
  expect "true" '.data.cargos.pageInfo.hasNextPage' "bo has a second page (GHI345)"
  resp="$(as "$BO" "$url" '{ cargos(first: 10) { edges { node { trackingId } } totalCount } }')"
  expect "3" '.data.cargos.totalCount' "bo's totalCount with all three edges"
  assert_error_shape "$resp" execution "$stack bo GHI345: execution error shape"
  case "$stack" in
    python)
      # Strawberry fails per key: one null node, one error.
      assert_error_count "$resp" 1 "$stack bo GHI345: one error"
      assert_error_extension "$resp" '["cargos","edges",2,"node"]' code '"SERVICE_UNAVAILABLE"' "$stack bo GHI345: the outage keeps its code"
      assert_error_message_at "$resp" '["cargos","edges",2,"node"]' "booking service unavailable" "$stack bo GHI345: the outage keeps its message"
      expect_project '["XYZ789","STU678",null]' .data.cargos.edges node.trackingId "bo: GHI345's edge is null, the siblings resolve"
      ;;
    quarkus)
      # SmallRye resolves a batch with one result list: one failing key fails all three nodes.
      assert_error_count "$resp" 3 "$stack bo GHI345: one error per node in the batch"
      assert_error_extension "$resp" '["cargos","edges",0,"node"]' code '"SERVICE_UNAVAILABLE"' "$stack bo GHI345: code at edge 0"
      assert_error_extension "$resp" '["cargos","edges",2,"node"]' code '"SERVICE_UNAVAILABLE"' "$stack bo GHI345: code at edge 2"
      expect_project '[null,null,null]' .data.cargos.edges node.trackingId "bo: the whole batch is lost (Chapter 13)"
      ;;
  esac
  resp="$(as "$BO" "$url" '{ cargo(trackingId: "ABC123") { trackingId } }')"
  assert_no_errors "$resp" "$stack bo asks for an ACME cargo"
  assert_null_at "$resp" '.data.cargo' "$stack bo: cargo(ABC123) is null"
  resp="$(as "$BO" "$url" '{ a: node(id: "cargo_ABC123") { id } b: node(id: "evt_1") { id } }')"
  assert_no_errors "$resp" "$stack bo node"
  expect_json '{"a":null,"b":null}' '.data' "bo: node(cargo_ABC123) and node(evt_1) are null"
  resp="$(as "$BO" "$url" '{ nodes(ids: ["cargo_ABC123", "cargo_XYZ789", "evt_1", "evt_3"]) { __typename ... on Cargo { trackingId } } }')"
  assert_no_errors "$resp" "$stack bo nodes"
  expect_json '[null,{"__typename":"Cargo","trackingId":"XYZ789"},null,null]' '.data.nodes' "bo: nodes keeps positions, null for what she may not see"

  # 6. ops: every cargo.
  resp="$(as "$OPS" "$url" '{ cargos(first: 10) { totalCount } }')"
  assert_no_errors "$resp" "$stack ops cargos"
  expect "6" '.data.cargos.totalCount' "ops sees all six cargos"
  resp="$(as "$OPS" "$url" '{ a: cargo(trackingId: "XYZ789") { trackingId } b: cargo(trackingId: "ABC123") { trackingId } }')"
  assert_no_errors "$resp" "$stack ops cargo"
  expect_json '{"a":{"trackingId":"XYZ789"},"b":{"trackingId":"ABC123"}}' '.data' "ops reads either shipper's cargo"

  # 7. Field level: registrationTime is for operators. An error with a code at
  #    the field's path; the null climbs to the nearest nullable parent, the
  #    edge's node, so both edges and their cursors survive.
  resp="$(as "$ANA" "$url" "$HISTORY")"
  assert_error_count "$resp" 2 "$stack ana registrationTime: one error per event"
  assert_error_path "$resp" '["cargo","handlingHistory","edges",0,"node","registrationTime"]' "$stack ana registrationTime: edge 0 path"
  assert_error_path "$resp" '["cargo","handlingHistory","edges",1,"node","registrationTime"]' "$stack ana registrationTime: edge 1 path"
  assert_error_extension "$resp" '["cargo","handlingHistory","edges",0,"node","registrationTime"]' code '"FORBIDDEN"' "$stack ana registrationTime: code"
  assert_error_message_at "$resp" '["cargo","handlingHistory","edges",0,"node","registrationTime"]' "operator role required" "$stack ana registrationTime: message"
  assert_body_not_contains "$resp" 'io.quarkus' "$stack ana registrationTime: no framework class name reaches the client"
  assert_body_not_contains "$resp" 'Exception' "$stack ana registrationTime: no exception name reaches the client"
  assert_null_at "$resp" '.data.cargo.handlingHistory.edges.0.node' "$stack ana: edge 0's node is null"
  assert_null_at "$resp" '.data.cargo.handlingHistory.edges.1.node' "$stack ana: edge 1's node is null"
  # Both edges survive with a non-empty cursor each: the cursors are siblings of
  # the failed node, not part of it.
  assert_eq "2 cursors, all non-empty" "$(project .data.cargo.handlingHistory.edges cursor | python3 -I -c '
import json, sys
cursors = json.load(sys.stdin)
ok = len(cursors) == 2 and all(isinstance(c, str) and c for c in cursors)
print("2 cursors, all non-empty" if ok else "bad cursors: %r" % (cursors,))
')" "$stack ana: both edges survive with their cursors"
  resp="$(as "$ANA" "$url" '{ node(id: "evt_1") { id ... on HandlingEvent { registrationTime } } }')"
  assert_null_at "$resp" '.data.node' "$stack the refused field nulls node, the nearest nullable parent"
  assert_error_path "$resp" '["node","registrationTime"]' "$stack node(evt_1).registrationTime: error path"
  assert_error_extension "$resp" '["node","registrationTime"]' code '"FORBIDDEN"' "$stack node(evt_1).registrationTime: code"
  resp="$(as "$ANA" "$url" '{ cargo(trackingId: "ABC123") { handlingHistory(first: 2) { edges { node { id completionTime } } } } }')"
  assert_no_errors "$resp" "$stack ana without registrationTime"
  expect_project '["evt_2","evt_1"]' .data.cargo.handlingHistory.edges node.id "ana: the rule is per field, the rest of the event is hers"
  resp="$(as "$OPS" "$url" "$HISTORY")"
  assert_no_errors "$resp" "$stack ops registrationTime"
  expect_project '["evt_2","evt_1"]' .data.cargo.handlingHistory.edges node.id "ops: history ids"
  expect_project '["2026-10-01T08:35:00Z","2026-09-30T16:05:00Z"]' .data.cargo.handlingHistory.edges node.registrationTime "ops reads registrationTime"

  # 8. Writes need the operator role. A refusal is a top-level error on a
  #    non-null payload, so data is null; nothing is written.
  source_calls_reset "$url"
  resp="$(as "$ANA" "$url" "$REGISTER" "$UNLOAD")"
  assert_null_at "$resp" '.data' "$stack ana's write nulls data (the payload is non-null)"
  assert_error_path "$resp" '["registerHandlingEvent"]' "$stack ana's write: error path"
  assert_error_extension "$resp" '["registerHandlingEvent"]' code '"FORBIDDEN"' "$stack ana's write: code"
  assert_error_message_at "$resp" '["registerHandlingEvent"]' "operator role required" "$stack ana's write: message"
  assert_body_not_contains "$resp" 'io.quarkus' "$stack ana's write: no framework class name reaches the client"
  assert_body_not_contains "$resp" 'Exception' "$stack ana's write: no exception name reaches the client"
  resp="$(gql "$url" "$REGISTER" "$UNLOAD")"
  assert_null_at "$resp" '.data' "$stack anonymous write nulls data"
  assert_error_extension "$resp" '["registerHandlingEvent"]' code '"UNAUTHENTICATED"' "$stack anonymous write: code"
  assert_body_not_contains "$resp" 'io.quarkus' "$stack anonymous write: no framework class name reaches the client"
  assert_body_not_contains "$resp" 'Exception' "$stack anonymous write: no exception name reaches the client"
  assert_source_call_count "$(source_calls "$url")" '*' '*' 0 "$stack refused writes make no source call"
  assert_source_call_count "$(source_calls "$url")" handling appendEvent 0 "$stack no handling.appendEvent"
  resp="$(as "$OPS" "$url" "$REGISTER" "$UNLOAD")"
  assert_no_errors "$resp" "$stack ops registers the unload"
  expect "evt_10" '.data.registerHandlingEvent.handlingEvent.id' "the unload is evt_10"
  expect "IN_PORT" '.data.registerHandlingEvent.cargo.delivery.transportStatus' "the payload's delivery sees the unload"
  assert_source_call_count "$(source_calls "$url")" handling appendEvent 1 "$stack ops' write reached the handling service"

  # 9. Tokens that do not validate are HTTP 401 with a Bearer challenge, before
  #    GraphQL runs, even for a public field.
  assert_rejected "$stack" "$url" "$(tamper "$ANA" signature)" "$stack tampered signature" || return 1
  assert_rejected "$stack" "$url" "$(tamper "$ANA" payload)" "$stack tampered payload (role escalation)" || return 1
  assert_rejected "$stack" "$url" "$OTHER" "$stack token for another audience" || return 1
  assert_rejected "$stack" "$url" "not.a.jwt" "$stack malformed token" || return 1
  # short-cli issues four-second tokens: fetched here, used at once, then used again after it lapsed.
  SHORT="$(oidc_token "$TOKEN_URL" short-cli ana ana-fixture-pw)"
  out="$(LGTM_BEARER="$SHORT" gql_any "$url" '{ location(unLocode: "NLRTM") { name } }')"
  assert_status_in "200" "$(status_of "$out")" "$stack the short-lived token works until it expires" || return 1
  sleep 5
  assert_rejected "$stack" "$url" "$SHORT" "$stack expired token" || return 1

  # 10. Concurrent callers keep their own identity: the viewer is read at each
  #     resolver's entry, including the batch resolvers that run after a source's
  #     latency, so ana's and bo's requests in flight together never mix.
  local scratch i
  scratch="$(mktemp -d)"
  on_exit "rm -rf '$scratch'"
  for i in 1 2 3 4 5 6; do
    (LGTM_BEARER="$ANA" gql "$url" '{ cargos(first: 3) { edges { node { trackingId } } } }' >"$scratch/ana$i" 2>&1) &
    (LGTM_BEARER="$BO" gql "$url" '{ cargos(first: 2) { edges { node { trackingId } } } }' >"$scratch/bo$i" 2>&1) &
  done
  wait
  for i in 1 2 3 4 5 6; do
    assert_json_eq '["VWX901","DEF456","ABC123"]' "$(json_field '.data.cargos.edges' <"$scratch/ana$i" | python3 -I -c 'import json,sys; print(json.dumps([e["node"]["trackingId"] for e in json.load(sys.stdin)]))')" "$stack concurrent ana request $i" || return 1
    assert_json_eq '["XYZ789","STU678"]' "$(json_field '.data.cargos.edges' <"$scratch/bo$i" | python3 -I -c 'import json,sys; print(json.dumps([e["node"]["trackingId"] for e in json.load(sys.stdin)]))')" "$stack concurrent bo request $i" || return 1
  done
  rm -rf "$scratch"

  # 11. The deprecation of Chapter 11, the custom scalars, and the live schema:
  #     authorization changes no field, argument or nullability. The schema is
  #     read anonymously: introspection is open in this chapter (Chapter 17 closes it).
  assert_deprecated "$url" Itinerary finalArrivalDate "Use \`finalArrivalTime\`." "$stack Itinerary.finalArrivalDate"
  assert_not_deprecated "$url" Itinerary finalArrivalTime "$stack Itinerary.finalArrivalTime"
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
  # Only Subscription is unserved: the canonical -> live breaking lines, less the
  # framework noise, are exactly its two removals.
  local sdl_rev sdl_removed
  sdl_rev="$(_sdl_diff "$CANONICAL_SDL_GLOB" "$url")"
  sdl_removed="$(grep '✖' <<<"$sdl_rev" | grep -vE "$LGTM_SDL_IGNORE" | sed -E 's/^.*✖ +//' | sort || true)"
  assert_eq "Schema subscription type Subscription was removed.
Type Subscription was removed" "$sdl_removed" "$stack only Subscription is unserved"

  echo "=== $stack: authentication and authorization check passed ==="
}

echo "=== Step 1: docker compose up ==="
compose_up "$COMPOSE_FILE" "$PROJECT"

echo
echo "=== Step 2: tokens from Keycloak ==="
wait_for_http "$REALM_URL" 180
ANA="$(oidc_token "$TOKEN_URL" tracking-cli ana ana-fixture-pw)"
BO="$(oidc_token "$TOKEN_URL" tracking-cli bo bo-fixture-pw)"
OPS="$(oidc_token "$TOKEN_URL" tracking-cli ops ops-fixture-pw)"
OTHER="$(oidc_token "$TOKEN_URL" other-cli ana ana-fixture-pw)"

echo
echo "=== Step 3: verify both stacks ==="
run_stack_check "quarkus" "http://localhost:8280/graphql"
run_stack_check "python" "http://localhost:8281/graphql"

echo
echo "PASS - Ch18 AuthN and AuthZ: Keycloak-issued JWTs are validated by Quarkus (quarkus-oidc) and" \
     "Python (PyJWT), operations need a signed-in caller or the operator role, a shipper sees only its" \
     "own cargos on every path (cargo, cargos with totalCount, node, nodes, edges), registrationTime is" \
     "an error with a code for non-operators and nulls only its edge node, tampered, wrong-audience" \
     "and expired tokens are HTTP 401, and both schemas still conform to the canonical SDL except for Subscription."
