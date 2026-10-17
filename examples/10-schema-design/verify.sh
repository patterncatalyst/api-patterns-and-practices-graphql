#!/usr/bin/env bash
# examples/10-schema-design/verify.sh
#
# Ch10 Schema design patterns: Query.nodes and the conventions of the schema,
# on both stacks.
#
# Steps: the refetch rule for each Node implementer (the id a field returns,
# handed to node(id:), returns the same object); nodes(ids:) keeps order, puts
# null at an unknown id and makes one source call per id (the N+1 that Chapter
# 13 batches); an empty list is an empty list; Node.possibleTypes; the live
# naming and payload conventions, read from one introspection request per
# stack; the GraphQL ESLint rules on the canonical SDL; a failed mutation still
# returns its payload; the scalars; conformance to the canonical SDL.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../_lib/lib.sh
source "$SCRIPT_DIR/../_lib/lib.sh"

PROJECT="gql-ch10-design"
COMPOSE_FILE="$SCRIPT_DIR/compose.yaml"
TMP_DIR="$(mktemp -d)"
on_exit rm -rf "$TMP_DIR"

# expect <expected> <json-path> <context> — assert one value of $resp.
expect() {
  assert_eq "$1" "$(json_field "$2" <<<"$resp")" "$stack $3"
}

# expect_json <expected-json> <json-path> <context> — assert an object, a list
# or a null of $resp by parsed equality.
expect_json() {
  assert_json_eq "$1" "$(json_field "$2" <<<"$resp")" "$stack $3"
}

# refetch <label> <obtain-query> <id-path> <expected-id> <typename> <fragment> <fragment-field-path> <expected>
# The refetch rule: the id a field returns, passed to node(id:), returns an
# object with the same id and the type it came from, and the fields selected
# through the inline fragment hold the seed values.
refetch() {
  local label="$1" obtain="$2" id_path="$3" want_id="$4" typename="$5" fragment="$6" field_path="$7" want="$8" id
  resp="$(gql "$url" "$obtain")"
  assert_no_errors "$resp" "$stack $label: obtain the id"
  id="$(json_field "$id_path" <<<"$resp")"
  assert_eq "$want_id" "$id" "$stack $label: the id the field returns"
  # shellcheck disable=SC2016  # a GraphQL variable, not a shell expansion
  resp="$(gql "$url" "query(\$id: ID!) { node(id: \$id) { id __typename $fragment } }" "{\"id\":\"$id\"}")"
  assert_no_errors "$resp" "$stack $label: node($id)"
  expect "$id" '.data.node.id' "$label: node(id:).id equals the id sent"
  expect "$typename" '.data.node.__typename' "$label: node(id:).__typename"
  expect "$want" ".data.node.$field_path" "$label: fragment field"
}

# conventions — print one line per offender and fail if there is any. Reads the
# whole schema from one introspection response on stdin.
conventions() {
  python3 -I -c '
import json, re, sys

schema = json.load(sys.stdin)["data"]["__schema"]
framework = re.compile("^(?:" + sys.argv[1] + ")$")
builtin = {"String", "Int", "Float", "Boolean", "ID"}
PASCAL = re.compile(r"^[A-Z][A-Za-z0-9]*$")
CAMEL = re.compile(r"^[a-z][A-Za-z0-9]*$")
SCREAMING = re.compile(r"^[A-Z][A-Z0-9_]*$")
offenders = []


def described(what, node):
    if not (node.get("description") or "").strip():
        offenders.append("no description: " + what)


def base(t):
    # (kind, name) of the innermost named type, and whether the outermost wrapper is NON_NULL.
    non_null = t["kind"] == "NON_NULL"
    while t.get("ofType"):
        t = t["ofType"]
    return t["kind"], t["name"], non_null


types = [t for t in schema["types"] if not t["name"].startswith("__") and t["name"] not in builtin
         and not framework.match(t["name"])]
roots = {schema["queryType"]["name"], (schema.get("mutationType") or {}).get("name")}
for t in types:
    name = t["name"]
    if not PASCAL.match(name):
        offenders.append("type name not PascalCase: " + name)
    described("type " + name, t)
    if t["kind"] == "INPUT_OBJECT" and not name.endswith("Input"):
        offenders.append("input object name does not end in Input: " + name)
    for f in t.get("fields") or []:
        where = name + "." + f["name"]
        if not CAMEL.match(f["name"]):
            offenders.append("field name not camelCase: " + where)
        described("field " + where, f)
        for a in f.get("args") or []:
            if not CAMEL.match(a["name"]):
                offenders.append("argument name not camelCase: %s(%s)" % (where, a["name"]))
            described("argument %s(%s)" % (where, a["name"]), a)
    for f in t.get("inputFields") or []:
        where = name + "." + f["name"]
        if not CAMEL.match(f["name"]):
            offenders.append("input field name not camelCase: " + where)
        described("input field " + where, f)
    for v in t.get("enumValues") or []:
        where = name + "." + v["name"]
        if not SCREAMING.match(v["name"]):
            offenders.append("enum value not SCREAMING_SNAKE_CASE: " + where)
        described("enum value " + where, v)
    if any(i["name"] == "Node" for i in t.get("interfaces") or []):
        ids = [f for f in t["fields"] if f["name"] == "id"]
        if not ids or base(ids[0]["type"]) != ("SCALAR", "ID", True):
            offenders.append("Node implementer without id: ID!: " + name)

mutation = next((t for t in schema["types"] if t["name"] == (schema.get("mutationType") or {}).get("name")), None)
for f in (mutation or {}).get("fields", []):
    where = "Mutation." + f["name"]
    args = f["args"]
    if [a["name"] for a in args] != ["input"]:
        offenders.append(where + " does not take exactly one argument named input")
    elif base(args[0]["type"])[0] != "INPUT_OBJECT" or not base(args[0]["type"])[2]:
        offenders.append(where + ": input is not a non-null input object")
    kind, name, non_null = base(f["type"])
    if kind != "OBJECT" or not non_null or not name.endswith("Payload"):
        offenders.append(where + " does not return a non-null ...Payload object")

for line in offenders:
    print(line)
sys.exit(1 if offenders else 0)
' "$LGTM_SDL_FRAMEWORK_TYPES"
}

# Everything a convention needs, in one request.
SCHEMA_QUERY='{ __schema { queryType { name } mutationType { name } types { name kind description interfaces { name } fields(includeDeprecated: true) { name description type { ...T } args { name description type { ...T } } } inputFields { name description } enumValues(includeDeprecated: true) { name description } } } }
fragment T on __Type { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name } } } } }'

# The helpers above read stack, url and resp from this function's scope.
# run_stack_check <stack> <url>
run_stack_check() {
  local stack="$1" url="$2" resp calls sorted offenders

  echo
  echo "=== verifying stack '$stack' at $url ==="

  wait_for_graphql "$url"

  # 1. The refetch rule, once per implementer of Node.
  refetch "Cargo" '{ cargo(trackingId: "ABC123") { id } }' '.data.cargo.id' "cargo_ABC123" \
    "Cargo" '... on Cargo { trackingId }' "trackingId" "ABC123"
  refetch "Location" '{ cargo(trackingId: "ABC123") { itinerary { legs { loadLocation { id } } } } }' \
    '.data.cargo.itinerary.legs.0.loadLocation.id' "loc_USNYC" \
    "Location" '... on Location { unLocode }' "unLocode" "USNYC"
  refetch "Voyage" '{ cargo(trackingId: "ABC123") { itinerary { legs { voyage { id } } } } }' \
    '.data.cargo.itinerary.legs.1.voyage.id' "voy_V200E" \
    "Voyage" '... on Voyage { number }' "number" "V200E"
  refetch "HandlingEvent" '{ node(id: "evt_1") { id } }' '.data.node.id' "evt_1" \
    "HandlingEvent" '... on HandlingEvent { type }' "type" "RECEIVE"

  # 2. nodes(ids:) keeps the order given, puts null at an unknown id, and
  #    resolves each id on its own: five ids, four source calls, and the
  #    repeated id is fetched twice.
  source_calls_reset "$url"
  resp="$(gql "$url" '{ nodes(ids: ["cargo_ABC123", "loc_NLRTM", "nope", "voy_V200E", "cargo_ABC123"]) { __typename } }')"
  assert_no_errors "$resp" "$stack nodes"
  expect_json '[{"__typename":"Cargo"},{"__typename":"Location"},null,{"__typename":"Voyage"},{"__typename":"Cargo"}]' \
    '.data.nodes' "nodes keeps the order and puts null at the unknown id"
  assert_source_calls_exactly "$(source_calls "$url")" \
    "booking.getCargo:ABC123,location.getLocation:NLRTM,voyage.getVoyage:V200E,booking.getCargo:ABC123" \
    "$stack nodes: one source call per known id"

  # The same list through inline fragments: the objects hold their values.
  resp="$(gql "$url" '{ nodes(ids: ["voy_V200E", "evt_1", "loc_NLRTM", "cargo_ABC123"]) { id ... on Voyage { number } ... on HandlingEvent { type } ... on Location { unLocode } ... on Cargo { trackingId } } }')"
  assert_no_errors "$resp" "$stack nodes with fragments"
  expect_json '[{"id":"voy_V200E","number":"V200E"},{"id":"evt_1","type":"RECEIVE"},{"id":"loc_NLRTM","unLocode":"NLRTM"},{"id":"cargo_ABC123","trackingId":"ABC123"}]' \
    '.data.nodes' "nodes through fragments"

  # 3. An empty list is an empty list, and nothing is called.
  source_calls_reset "$url"
  resp="$(gql "$url" '{ nodes(ids: []) { id } }')"
  assert_no_errors "$resp" "$stack nodes(ids: [])"
  expect_json '[]' '.data.nodes' "nodes(ids: []) is []"
  assert_source_calls_exactly "$(source_calls "$url")" "" "$stack nodes(ids: []) calls no source"

  # A bare prefix and an empty key are unrecognised ids: null, no source call.
  source_calls_reset "$url"
  resp="$(gql "$url" '{ nodes(ids: ["cargo", "evt", "cargo_"]) { id } }')"
  assert_no_errors "$resp" "$stack nodes with bare prefixes"
  expect_json '[null,null,null]' '.data.nodes' "bare prefixes and an empty key give null"
  assert_source_calls_exactly "$(source_calls "$url")" "" "$stack nodes with bare prefixes calls no source"

  # 4. Node's implementers, as the schema reports them.
  resp="$(gql "$url" '{ __type(name: "Node") { kind possibleTypes { name } } }')"
  assert_no_errors "$resp" "$stack Node introspection"
  expect "INTERFACE" '.data.__type.kind' "Node kind"
  sorted="$(python3 -I -c '
import json, sys
print(json.dumps(sorted(t["name"] for t in json.load(sys.stdin)["data"]["__type"]["possibleTypes"])))
' <<<"$resp")"
  assert_json_eq '["Cargo","HandlingEvent","Location","Voyage"]' "$sorted" "$stack Node.possibleTypes"

  # nodes is declared as the contract says: a non-null list of nullable Nodes
  # that takes a non-null list of non-null ids.
  # shellcheck disable=SC2016
  resp="$(gql "$url" '{ __type(name: "Query") { fields { name description type { kind ofType { kind ofType { kind name } } } args { name type { kind ofType { kind ofType { kind ofType { kind name } } } } } } } }')"
  assert_no_errors "$resp" "$stack Query.nodes introspection"
  assert_json_eq '{"name":"nodes","description":"Fetch several objects by their global ids, in the order given. An unknown id yields null at its position.","type":{"kind":"NON_NULL","ofType":{"kind":"LIST","ofType":{"kind":"INTERFACE","name":"Node"}}},"args":[{"name":"ids","type":{"kind":"NON_NULL","ofType":{"kind":"LIST","ofType":{"kind":"NON_NULL","ofType":{"kind":"SCALAR","name":"ID"}}}}}]}' \
    "$(python3 -I -c '
import json, sys
print(json.dumps(next(f for f in json.load(sys.stdin)["data"]["__type"]["fields"] if f["name"] == "nodes")))
' <<<"$resp")" "$stack Query.nodes signature"

  # 5. The conventions, read from the live schema: one request, one checker.
  resp="$(gql "$url" "$SCHEMA_QUERY")"
  assert_no_errors "$resp" "$stack __schema"
  printf '%s\n' "$resp" >"$TMP_DIR/$stack-schema.json"
  if ! offenders="$(conventions <"$TMP_DIR/$stack-schema.json")"; then
    echo "lib.sh: FAIL — $stack schema conventions:" >&2
    echo "$offenders" >&2
    return 1
  fi
  echo "lib.sh: ok — $stack schema conventions: names, input and payload shapes, descriptions, Node ids" >&2

  # 7. A mutation that fails a domain rule still returns its payload: the
  #    field is non-null, the failure is data, and there is no top-level error.
  # shellcheck disable=SC2016
  resp="$(gql "$url" 'mutation($i: RegisterHandlingEventInput!) { registerHandlingEvent(input: $i) { handlingEvent { id } userErrors { code field } } }' \
    '{"i":{"trackingId":"ABC123","type":"RECEIVE","location":"USNYC","voyageNumber":"V100S","completionTime":"2026-09-30T16:00:00Z"}}')"
  assert_no_errors "$resp" "$stack failing mutation"
  assert_null_at "$resp" '.data.registerHandlingEvent.handlingEvent' "$stack failing mutation has no event"
  assert_eq "1" "$(json_field '.data.registerHandlingEvent.userErrors' <<<"$resp" | json_len .)" "$stack one userError"
  expect_json '[{"code":"VOYAGE_NOT_ALLOWED","field":["input","voyageNumber"]}]' \
    '.data.registerHandlingEvent.userErrors' "the failure is data, in the payload"

  # 8. The custom scalars are real scalars and carry the canonical @specifiedBy
  #    URL (none for TrackingId). The SDL diff covers types, fields and
  #    arguments; this loop checks specifiedByURL.
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

  # 9. The live schema conforms to the canonical SDL. Query.nodes is served now;
  #    Subscription, cargos and handlingHistory are slice removals.
  assert_sdl_conforms "$url" "$stack schema vs contracts/schema"

  echo "=== $stack: schema design check passed ==="
}

echo "=== Step 1: docker compose up ==="
compose_up "$COMPOSE_FILE" "$PROJECT"

echo
echo "=== Step 2: lint the canonical SDL ==="
# GraphQL ESLint with the naming and description rules in contracts/.
ensure_contracts_tools
npm --prefix "$REPO_ROOT/contracts" run lint

echo
echo "=== Step 3: verify both stacks ==="
run_stack_check "quarkus" "http://localhost:8200/graphql"
run_stack_check "python" "http://localhost:8201/graphql"

echo
echo "PASS - Ch10 Schema design patterns: Quarkus (SmallRye GraphQL) and Python" \
     "(Strawberry) both refetch every Node implementer by its id, serve Query.nodes in" \
     "request order with null for an unknown id and one source call per id, report the" \
     "four implementers of Node, follow the naming, input, payload and description" \
     "conventions in the live schema, return a failing mutation as a payload, and conform" \
     "to the canonical SDL."

# Explicit teardown in addition to lib.sh's EXIT trap (belt-and-suspenders);
# compose_down is idempotent/safe to call twice.
compose_down "$COMPOSE_FILE" "$PROJECT"
