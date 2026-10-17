#!/usr/bin/env bash
# examples/11-evolution/verify.sh
#
# Ch11 Evolution and versioning: a deprecated field that still executes, and the
# breaking gate run on fixtures.
#
# Steps: lint the canonical SDL; on each stack, the deprecated finalArrivalDate
# and its replacement finalArrivalTime return the same instant, introspection
# flags exactly one deprecated element, `fields` hides it unless
# includeDeprecated is true, the scalars, and conformance to the canonical SDL;
# then, once, contracts/scripts/breaking.sh on fixture directories, from "no
# change" to "deliberate removal".
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../_lib/lib.sh
source "$SCRIPT_DIR/../_lib/lib.sh"

PROJECT="gql-ch11-evolution"
COMPOSE_FILE="$SCRIPT_DIR/compose.yaml"
TMP_DIR="$(mktemp -d)"
on_exit rm -rf "$TMP_DIR"

REASON='Use `finalArrivalTime`.'
ARRIVAL="2026-10-11T18:00:00Z"

# expect <expected> <json-path> <context> — assert one value of $resp.
expect() {
  assert_eq "$1" "$(json_field "$2" <<<"$resp")" "$stack $3"
}

# The names of the type's fields as a sorted JSON list, from an introspection
# response on stdin.
field_names() {
  python3 -I -c '
import json, sys
print(json.dumps(sorted(f["name"] for f in json.load(sys.stdin)["data"]["__type"]["fields"])))
'
}

# Every deprecated element of the schema, as "Type.member" entries in a sorted
# JSON list: output fields, arguments, input fields and enum values.
deprecated_elements() {
  python3 -I -c '
import json, sys

found = []
for t in json.load(sys.stdin)["data"]["__schema"]["types"]:
    if t["name"].startswith("__"):
        continue
    for key in ("fields", "inputFields", "enumValues"):
        for m in t.get(key) or []:
            if m["isDeprecated"]:
                found.append(t["name"] + "." + m["name"])
            for a in m.get("args") or []:
                if a["isDeprecated"]:
                    found.append(t["name"] + "." + m["name"] + "(" + a["name"] + ")")
print(json.dumps(sorted(found)))
'
}

DEPRECATED_QUERY='{ __schema { types { name
  fields(includeDeprecated: true) { name isDeprecated args(includeDeprecated: true) { name isDeprecated } }
  inputFields(includeDeprecated: true) { name isDeprecated }
  enumValues(includeDeprecated: true) { name isDeprecated } } } }'

# The helpers above read stack, url and resp from this function's scope.
# run_stack_check <stack> <url>
run_stack_check() {
  local stack="$1" url="$2" resp sorted

  echo
  echo "=== verifying stack '$stack' at $url ==="

  wait_for_graphql "$url"

  # 1. Both fields hold one value, and the deprecated one still executes: no
  #    errors, no warning in the response.
  resp="$(gql "$url" '{ cargo(trackingId: "ABC123") { itinerary { finalArrivalTime finalArrivalDate } } }')"
  assert_no_errors "$resp" "$stack both arrival fields"
  expect "$ARRIVAL" '.data.cargo.itinerary.finalArrivalTime' "finalArrivalTime"
  expect "$ARRIVAL" '.data.cargo.itinerary.finalArrivalDate' "finalArrivalDate (deprecated) still executes"
  assert_body_not_contains "$resp" "deprecat" "$stack a deprecated field adds nothing to the response"

  # A client that selects only the deprecated field is served as before.
  resp="$(gql "$url" '{ cargo(trackingId: "ABC123") { itinerary { finalArrivalDate } } }')"
  assert_no_errors "$resp" "$stack finalArrivalDate alone"
  expect "$ARRIVAL" '.data.cargo.itinerary.finalArrivalDate' "finalArrivalDate alone"

  # The ETA in Cargo.delivery is derived from the replacement field.
  resp="$(gql "$url" '{ cargo(trackingId: "ABC123") { delivery { estimatedTimeOfArrival } } }')"
  assert_no_errors "$resp" "$stack delivery"
  expect "$ARRIVAL" '.data.cargo.delivery.estimatedTimeOfArrival' "estimatedTimeOfArrival"

  # 2. The flag and the reason, as introspection reports them.
  assert_deprecated "$url" Itinerary finalArrivalDate "$REASON" "$stack Itinerary.finalArrivalDate" || return 1
  assert_not_deprecated "$url" Itinerary finalArrivalTime "$stack Itinerary.finalArrivalTime" || return 1

  # Exactly one element of the whole schema is deprecated.
  resp="$(gql "$url" "$DEPRECATED_QUERY")"
  assert_no_errors "$resp" "$stack deprecated elements"
  assert_json_eq '["Itinerary.finalArrivalDate"]' "$(deprecated_elements <<<"$resp")" \
    "$stack the only deprecated element in the schema"

  # 3. `fields` hides a deprecated field unless includeDeprecated is true.
  resp="$(gql "$url" '{ __type(name: "Itinerary") { fields { name } } }')"
  assert_no_errors "$resp" "$stack fields default"
  assert_json_eq '["finalArrivalTime","legs"]' "$(field_names <<<"$resp")" \
    "$stack fields hides the deprecated field by default"
  resp="$(gql "$url" '{ __type(name: "Itinerary") { fields(includeDeprecated: false) { name } } }')"
  assert_no_errors "$resp" "$stack fields includeDeprecated false"
  assert_json_eq '["finalArrivalTime","legs"]' "$(field_names <<<"$resp")" \
    "$stack fields(includeDeprecated: false)"
  resp="$(gql "$url" '{ __type(name: "Itinerary") { fields(includeDeprecated: true) { name } } }')"
  assert_no_errors "$resp" "$stack fields includeDeprecated true"
  assert_json_eq '["finalArrivalDate","finalArrivalTime","legs"]' "$(field_names <<<"$resp")" \
    "$stack fields(includeDeprecated: true) lists it"

  # What removal would look like to a client: a selection the schema does not
  # have fails validation, so the request is rejected before any resolver runs.
  resp="$(gql_any "$url" '{ cargo(trackingId: "ABC123") { itinerary { finalArrivalDay } } }')" || return 1
  assert_status_in "200 400" "$(status_of "$resp")" "$stack a field the schema lacks: status"
  resp="$(body_of "$resp")"
  assert_has_errors "$resp" "$stack a field the schema lacks is rejected"
  assert_no_data "$resp" "$stack a rejected request returns no data"
  assert_error_message_contains "$resp" "finalArrivalDay" "$stack the message names the field"

  # 7. The custom scalars are real scalars and carry the canonical @specifiedBy
  #    URL (none for TrackingId). The SDL diff covers types, fields and
  #    arguments; this loop checks specifiedByURL.
  local scalar
  for scalar in TrackingId UnLocode DateTime; do
    # shellcheck disable=SC2016  # a GraphQL variable, not a shell expansion
    resp="$(gql "$url" 'query Kind($n: String!) { __type(name: $n) { kind specifiedByURL } }' "{\"n\":\"$scalar\"}")"
    assert_no_errors "$resp" "$stack $scalar introspection"
    expect "SCALAR" '.data.__type.kind' "$scalar kind"
    case "$scalar" in
      UnLocode) expect "https://unece.org/trade/uncefact/unlocode" '.data.__type.specifiedByURL' "$scalar specifiedByURL" ;;
      DateTime) expect "https://www.rfc-editor.org/rfc/rfc3339" '.data.__type.specifiedByURL' "$scalar specifiedByURL" ;;
      *) assert_null_at "$resp" '.data.__type.specifiedByURL' "$stack $scalar has no specifiedByURL" ;;
    esac
  done

  # 4. The live schema conforms to the canonical SDL. Query.cargos,
  #    Cargo.handlingHistory and Subscription are slice removals.
  assert_sdl_conforms "$url" "$stack schema vs contracts/schema"

  echo "=== $stack: evolution check passed ==="
}

# --- Gate fixtures -----------------------------------------------------------
# No fixture file is committed. Each case copies contracts/schema twice, applies
# one textual edit to a copy, and runs contracts/scripts/breaking.sh on the
# pair. Every edit replaces text that must occur exactly once in its file; a
# fixture that did not apply is a failure, never a pass.

CANONICAL="$REPO_ROOT/contracts/schema"
DQ='"""'    # a GraphQL block-string delimiter
DEPRECATED_DIRECTIVE=' @deprecated(reason: "Use `finalArrivalTime`.")'

# edit <file> <old> <new> — replace <old> by <new>, which must occur once.
edit() {
  python3 -I -c '
import sys

path, old, new = sys.argv[1:4]
text = open(path, encoding="utf-8").read()
if text.count(old) != 1:
    sys.exit("fixture did not apply: %d occurrences in %s of %r" % (text.count(old), path, old))
open(path, "w", encoding="utf-8").write(text.replace(old, new))
' "$@" || { echo "lib.sh: FAIL — fixture did not apply: $1" >&2; return 1; }
}

# fixture <name> — make $TMP_DIR/<name>/base and /new, both the canonical schema.
fixture() {
  rm -rf "${TMP_DIR:?}/$1"
  mkdir -p "$TMP_DIR/$1"
  cp -r "$CANONICAL" "$TMP_DIR/$1/base"
  cp -r "$CANONICAL" "$TMP_DIR/$1/new"
}

# gate_case <name> <rc> <needle> [rules] — assert the gate on $TMP_DIR/<name>.
gate_case() {
  assert_gate "$2" "$3" "$TMP_DIR/$1/base" "$TMP_DIR/$1/new" "${4:-}" "gate $1 (exit $2)"
}

run_gate_fixtures() {
  local d cargo handling location root

  echo
  echo "=== gate: contracts/scripts/breaking.sh on fixtures ==="

  # 1. No change.
  fixture no-change
  gate_case no-change 0 "No changes detected"

  # 2. The real Chapter 11 change: the base is the contract before it, the new
  #    side is the contract as it stands.
  fixture real-change
  d="$TMP_DIR/real-change/base/shipping"
  edit "$d/cargo.graphql" "  ${DQ}When the final leg arrives.${DQ}
  finalArrivalTime: DateTime!
" ""
  edit "$d/cargo.graphql" "$DEPRECATED_DIRECTIVE" ""
  gate_case real-change 0 "✔  Field Itinerary.finalArrivalDate is deprecated"
  gate_case real-change 0 "✔  Field finalArrivalTime was added to object type Itinerary"

  # 3. Safe: add an optional field.
  fixture add-field
  location="$TMP_DIR/add-field/new/shipping/location.graphql"
  edit "$location" "  country: String!
}" "  country: String!
  ${DQ}IANA time zone, for example \`Europe/Amsterdam\`.${DQ}
  timeZone: String
}"
  gate_case add-field 0 "✔  Field timeZone was added to object type Location"
  gate_case add-field 0 "✔  Field timeZone was added to object type Location" dangerousBreaking

  # 4. Safe: add an optional input field.
  fixture add-input-field
  handling="$TMP_DIR/add-input-field/new/shipping/handling.graphql"
  edit "$handling" "  idempotencyKey: String
}" "  idempotencyKey: String
  ${DQ}The operator who handled the cargo.${DQ}
  operatorId: String
}"
  gate_case add-input-field 0 "✔  Input field operatorId of type String was added to input object type RegisterHandlingEventInput"

  # 5. Safe: tighten an output (nullable to non-null).
  fixture tighten-output
  cargo="$TMP_DIR/tighten-output/new/shipping/cargo.graphql"
  edit "$cargo" "  itinerary: Itinerary
" "  itinerary: Itinerary!
"
  gate_case tighten-output 0 "✔  Field Cargo.itinerary changed type from Itinerary to Itinerary!"

  # 6 and 7. Dangerous: a new enum value. The default gate passes and flags it;
  #          the strict rule fails on it.
  fixture add-enum-value
  handling="$TMP_DIR/add-enum-value/new/shipping/handling.graphql"
  edit "$handling" "  CLAIM
}" "  CLAIM
  ${DQ}Moved between vessels at an intermediate port.${DQ}
  TRANSSHIP
}"
  gate_case add-enum-value 0 "⚠  Enum value TRANSSHIP was added to enum HandlingEventType"
  gate_case add-enum-value 1 "✖  Enum value TRANSSHIP was added to enum HandlingEventType" dangerousBreaking

  # On a pull request (GITHUB_ACTIONS=true) the same dangerous line also becomes
  # a ::warning annotation, and the gate still passes.
  local annotated rc=0
  annotated="$(env GITHUB_ACTIONS=true BASE_DIR="$TMP_DIR/add-enum-value/base" NEW_DIR="$TMP_DIR/add-enum-value/new" \
    bash "$CONTRACTS_DIR/scripts/breaking.sh" 2>&1)" || rc=$?
  assert_eq "0" "$rc" "the dangerous change passes under GITHUB_ACTIONS" || return 1
  assert_contains "::warning title=Dangerous schema change::" "$annotated" "the dangerous line is annotated" || return 1
  assert_contains "Enum value TRANSSHIP was added to enum HandlingEventType" \
    "$(grep '::warning' <<<"$annotated")" "the annotation carries the change line" || return 1

  # 8. Dangerous: a new optional argument.
  fixture add-argument
  root="$TMP_DIR/add-argument/new/shipping/schema.graphql"
  edit "$root" "    routingStatus: RoutingStatus
  ): CargoConnection!" "    routingStatus: RoutingStatus
    ${DQ}Only cargos bound for this destination.${DQ}
    destination: UnLocode
  ): CargoConnection!"
  gate_case add-argument 0 "⚠  Argument destination: UnLocode added to field Query.cargos"

  # 9. Breaking: remove a field.
  fixture remove-field
  cargo="$TMP_DIR/remove-field/new/shipping/cargo.graphql"
  edit "$cargo" "  ${DQ}When the cargo is unloaded.${DQ}
  unloadTime: DateTime!
" ""
  gate_case remove-field 1 "✖  Field unloadTime was removed from object type Leg"

  # 10. Breaking: loosen an output (non-null to nullable).
  fixture loosen-output
  cargo="$TMP_DIR/loosen-output/new/shipping/cargo.graphql"
  edit "$cargo" "  trackingId: TrackingId!" "  trackingId: TrackingId"
  gate_case loosen-output 1 "✖  Field Cargo.trackingId changed type from TrackingId! to TrackingId"

  # 11. Breaking: a required input field.
  fixture required-input
  handling="$TMP_DIR/required-input/new/shipping/handling.graphql"
  edit "$handling" "  idempotencyKey: String
}" "  idempotencyKey: String
  ${DQ}The operator who handled the cargo.${DQ}
  operatorId: String!
}"
  gate_case required-input 1 "✖  Input field operatorId of type String! was added to input object type RegisterHandlingEventInput"

  # 12. Breaking: remove an enum value.
  fixture remove-enum-value
  cargo="$TMP_DIR/remove-enum-value/new/shipping/cargo.graphql"
  edit "$cargo" "  ${DQ}Whereabouts unknown.${DQ}
  UNKNOWN
" ""
  gate_case remove-enum-value 1 "✖  Enum value UNKNOWN was removed from enum TransportStatus"

  # 13 and 14. The lifecycle's last step: removing the deprecated field fails;
  #            the suppressRemovalOfDeprecatedField rule downgrades it.
  fixture remove-deprecated
  cargo="$TMP_DIR/remove-deprecated/new/shipping/cargo.graphql"
  edit "$cargo" "  ${DQ}When the final leg arrives.${DQ}
  finalArrivalDate: DateTime!${DEPRECATED_DIRECTIVE}
" ""
  gate_case remove-deprecated 1 "✖  Field finalArrivalDate (deprecated) was removed from object type Itinerary"
  gate_case remove-deprecated 0 "⚠  Field finalArrivalDate (deprecated) was removed from object type Itinerary" \
    suppressRemovalOfDeprecatedField

  # Nullability on an input runs the other way from an output: requiring a value
  # that was optional breaks the clients that omit it; accepting null where a
  # value was required breaks nobody.
  fixture tighten-input
  handling="$TMP_DIR/tighten-input/new/shipping/handling.graphql"
  edit "$handling" "  voyageNumber: String
" "  voyageNumber: String!
"
  gate_case tighten-input 1 "✖  Input field RegisterHandlingEventInput.voyageNumber changed type from String to String!"

  fixture loosen-input
  handling="$TMP_DIR/loosen-input/new/shipping/handling.graphql"
  edit "$handling" "  completionTime: DateTime!
  ${DQ}Client" "  completionTime: DateTime
  ${DQ}Client"
  gate_case loosen-input 0 "✔  Input field RegisterHandlingEventInput.completionTime changed type from DateTime! to DateTime"

  # Three more changes the chapters before this one called dangerous or safe: a
  # member added to a union, an existing type that starts to implement an
  # interface, and a new type that implements one.
  fixture add-union-member
  d="$TMP_DIR/add-union-member"
  printf '%s\nunion SearchResult = Cargo | Location\n' "${DQ}A search hit.${DQ}" >"$d/base/shipping/search.graphql"
  printf '%s\nunion SearchResult = Cargo | Location | Voyage\n' "${DQ}A search hit.${DQ}" >"$d/new/shipping/search.graphql"
  gate_case add-union-member 0 "⚠  Member Voyage was added to Union type SearchResult"

  fixture implement-interface
  cargo="$TMP_DIR/implement-interface/new/shipping/cargo.graphql"
  edit "$cargo" "type Leg {
" "type Leg implements Node {
  ${DQ}The globally unique identifier of this leg.${DQ}
  id: ID!
"
  gate_case implement-interface 0 "⚠  Leg object implements Node interface"

  fixture new-implementer
  printf '%s\ntype Vessel implements Node {\n  %s\n  id: ID!\n}\n' "${DQ}A vessel.${DQ}" "${DQ}The globally unique identifier of this vessel.${DQ}" \
    >"$TMP_DIR/new-implementer/new/shipping/vessel.graphql"
  gate_case new-implementer 0 "✔  Type Vessel was added"

  # The scope of the conformance check: a schema that lacks only the
  # deprecation still conforms, because assert_sdl_conforms fails on breaking
  # changes and the loss of @deprecated is a safe one.
  fixture undeprecated
  d="$TMP_DIR/undeprecated/new/shipping"
  edit "$d/cargo.graphql" "$DEPRECATED_DIRECTIVE" ""
  gate_case undeprecated 0 "✔  Field Itinerary.finalArrivalDate is no longer deprecated"
  assert_sdl_conforms "$TMP_DIR/undeprecated/new/**/*.graphql" \
    "a schema without the deprecation still conforms" || return 1

  echo "=== gate: fixtures passed ==="
}

echo "=== Step 1: docker compose up ==="
compose_up "$COMPOSE_FILE" "$PROJECT"

echo
echo "=== Step 2: lint the canonical SDL ==="
# GraphQL ESLint with the naming and description rules in contracts/. The pinned
# tools may not be installed yet (a CI runner), so install them first.
ensure_contracts_tools
npm --prefix "$REPO_ROOT/contracts" run lint

echo
echo "=== Step 3: verify both stacks ==="
run_stack_check "quarkus" "http://localhost:8210/graphql"
run_stack_check "python" "http://localhost:8211/graphql"

echo
echo "=== Step 4: the breaking gate on fixtures ==="
run_gate_fixtures

echo
echo "PASS - Ch11 Evolution and versioning: Quarkus (SmallRye GraphQL) and Python" \
     "(Strawberry) both serve finalArrivalTime and the deprecated finalArrivalDate with" \
     "one value, flag exactly that field as deprecated with its reason, hide it from" \
     "fields unless includeDeprecated is true and conform to the canonical SDL; the" \
     "breaking gate passes safe and dangerous changes, fails breaking ones and fails" \
     "dangerous ones in strict mode, on every fixture case."

# Explicit teardown in addition to lib.sh's EXIT trap (belt-and-suspenders);
# compose_down is idempotent/safe to call twice.
compose_down "$COMPOSE_FILE" "$PROJECT"
