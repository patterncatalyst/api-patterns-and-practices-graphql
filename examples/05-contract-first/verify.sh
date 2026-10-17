#!/usr/bin/env bash
# examples/05-contract-first/verify.sh
#
# Ch5 Schema-first and contract-first: both stacks stay code-first and serve
# the Ch3 slice of the canonical SDL. This script closes the loop around that
# arrangement. It exports the schema each stack builds as SDL (an HTTP GET on
# Quarkus, the strawberry CLI inside the python container), diffs the exports
# and the live introspection against contracts/schema/ with graphql-inspector,
# lints the canonical SDL, and then seeds five kinds of drift into copies of
# each export to prove that the gate fails, and fails on the right line.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../_lib/lib.sh
source "$SCRIPT_DIR/../_lib/lib.sh"

PROJECT="gql-ch05-contract"
COMPOSE_FILE="$SCRIPT_DIR/compose.yaml"

# One scratch directory for the exports and the seeded-drift copies.
TMP_DIR="$(mktemp -d)"

# fail <message> - print a FAIL line and return non-zero.
fail() {
  echo "verify.sh: FAIL - $*" >&2
  return 1
}

# expect <expected> <json-path> <context> - assert one value of $resp.
expect() {
  assert_eq "$1" "$(json_field "$2" <<<"$resp")" "$stack $3"
}

# export_schema <stack> <url> - write the SDL a stack exports to $TMP_DIR/<stack>.graphql.
#   quarkus: SmallRye serves its schema at GET /graphql/schema.graphql.
#   python:  the strawberry CLI prints the schema of app.schema:schema; it runs
#            inside the container, where the application's code and its
#            dependencies live.
export_schema() {
  local stack="$1" url="$2" out="$TMP_DIR/$1.graphql"
  case "$stack" in
    quarkus) curl -fsS --max-time 30 "$(graphql_base "$url")/graphql/schema.graphql" -o "$out" ;;
    python) docker compose -p "$PROJECT" -f "$COMPOSE_FILE" exec -T python \
              strawberry export-schema app.schema:schema >"$out" ;;
  esac
  [[ -s "$out" ]] || fail "$stack export is empty"
  grep -qF 'type Cargo implements Node' "$out" || fail "$stack export has no 'type Cargo implements Node'"
  echo "verify.sh: $stack exported $(wc -l <"$out") lines of SDL" >&2
}

# seed_drift <case> <source-sdl> <drifted-sdl> - copy an export with one edit.
# The Cargo edits are scoped to the Cargo type so they cannot touch the
# Query.cargo argument (also written "trackingId: TrackingId!"). A fixture whose
# edit matched nothing leaves the copy identical to the export: that is a
# failure of the fixture, never a pass of the gate.
seed_drift() {
  local name="$1" src="$2" dst="$3"
  case "$name" in
    tighten)
      sed -e '/^type Cargo implements Node {/,/^}/ s/^\(  itinerary: Itinerary\)$/\1!/' "$src" >"$dst" ;;
    loosen)
      sed -e '/^type Cargo implements Node {/,/^}/ s/^\(  trackingId: TrackingId\)!$/\1/' "$src" >"$dst" ;;
    extra-field)
      sed -e '/^type Cargo implements Node {/a\  weightKg: Float' "$src" >"$dst" ;;
    enum-value)
      # Removes the value and its description line: a description left dangling
      # before the closing brace would be a syntax error, not drift.
      sed -z -e 's/\n *"[^\n]*"\n *UNKNOWN\n/\n/' "$src" >"$dst" ;;
    description)
      sed -e 's/The public tracking identifier\./Tracking id./' "$src" >"$dst" ;;
    *) fail "unknown drift case $name" ;;
  esac
  if cmp -s "$src" "$dst"; then
    fail "drift fixture '$name' did not apply to $src"
  fi
}

# check_drift <stack> <case> <needle>
check_drift() {
  local stack="$1" name="$2" needle="$3"
  local drifted="$TMP_DIR/$stack-$name.graphql"
  seed_drift "$name" "$TMP_DIR/$stack.graphql" "$drifted"
  assert_sdl_drift "$drifted" "$needle" "$stack $name drift"
}

# The helpers above read stack, url and resp from this function's scope.
run_stack_check() {
  local stack="$1" url="$2" resp

  echo
  echo "=== verifying stack '$stack' at $url ==="

  wait_for_graphql "$url"

  # 1. Sanity: the Ch3 slice still answers with the seed values.
  # shellcheck disable=SC2016  # GraphQL variables, not shell expansions
  resp="$(gql "$url" 'query Cargo($t: TrackingId!) { cargo(trackingId: $t) { trackingId delivery { transportStatus } } }' '{"t":"ABC123"}')"
  assert_no_errors "$resp" "$stack cargo(ABC123)"
  expect "ABC123" '.data.cargo.trackingId' "cargo.trackingId"
  expect "ONBOARD_CARRIER" '.data.cargo.delivery.transportStatus' "delivery.transportStatus"

  # 2. The scalars have kind SCALAR in the live schema. Introspection carries
  #    @specifiedBy as specifiedByURL, which this loop reads on both stacks.
  local scalar specified_by
  for scalar in TrackingId UnLocode DateTime; do
    case "$scalar" in
      UnLocode) specified_by="https://unece.org/trade/uncefact/unlocode" ;;
      DateTime) specified_by="https://www.rfc-editor.org/rfc/rfc3339" ;;
      *) specified_by="null" ;;
    esac
    # shellcheck disable=SC2016
    resp="$(gql "$url" 'query Kind($n: String!) { __type(name: $n) { kind specifiedByURL } }' "{\"n\":\"$scalar\"}")"
    assert_no_errors "$resp" "$stack $scalar introspection"
    expect "SCALAR" '.data.__type.kind' "$scalar kind"
    if [[ "$specified_by" == "null" ]]; then
      assert_null_at "$resp" '.data.__type.specifiedByURL' "$stack $scalar has no specifiedByURL"
    else
      expect "$specified_by" '.data.__type.specifiedByURL' "$scalar specifiedByURL"
    fi
  done

  # 3. Export the schema this stack builds.
  export_schema "$stack" "$url"
  local exported="$TMP_DIR/$stack.graphql"

  # 4. The export and the live schema each conform to the canonical SDL.
  assert_sdl_conforms "$exported" "$stack export vs contracts/schema"
  assert_sdl_conforms "$url" "$stack introspection vs contracts/schema"

  # 5. What the export carries differs from what introspection carries: both
  #    stacks print the three custom scalars, but only Strawberry prints the
  #    @specifiedBy directive on them. SmallRye reports the URL through
  #    introspection (step 2) and leaves it out of the exported file.
  grep -qF 'scalar DateTime' "$exported" || fail "$stack export does not declare scalar DateTime"
  grep -qF 'scalar UnLocode' "$exported" || fail "$stack export does not declare scalar UnLocode"
  case "$stack" in
    quarkus) ! grep -qF '@specifiedBy' "$exported" || fail "quarkus export now prints @specifiedBy" ;;
    python) grep -qF 'scalar UnLocode @specifiedBy(url: "https://unece.org/trade/uncefact/unlocode")' "$exported" \
              || fail "python export lost @specifiedBy on UnLocode" ;;
  esac

  # 6. Seeded drift, each case run against this stack's own export. The needle
  #    must appear in graphql-inspector's change line, not just in a context
  #    string.
  check_drift "$stack" tighten "Cargo.itinerary"
  check_drift "$stack" loosen "Cargo.trackingId"
  check_drift "$stack" extra-field "weightKg"
  check_drift "$stack" enum-value "UNKNOWN"
  check_drift "$stack" description "Cargo.trackingId"

  echo "=== $stack: contract check passed ==="
}

echo "=== Step 1: docker compose up ==="
compose_up "$COMPOSE_FILE" "$PROJECT"
# compose_up registered the EXIT trap that tears the stack down. Chain the
# removal of the scratch directory after it.
trap 'rc=$?; _lib_teardown "$rc"; rm -rf "$TMP_DIR"; exit "$rc"' EXIT

echo
echo "=== Step 2: verify both stacks ==="
run_stack_check "quarkus" "http://localhost:8150/graphql"
run_stack_check "python" "http://localhost:8151/graphql"

echo
echo "=== Step 3: two stacks, one schema ==="
assert_sdl_same "$TMP_DIR/quarkus.graphql" "$TMP_DIR/python.graphql" "quarkus export vs python export"

echo
echo "=== Step 4: lint the canonical SDL ==="
ensure_contracts_tools
npm --prefix "$CONTRACTS_DIR" run lint

echo
echo "PASS - Ch5 Schema-first and contract-first: Quarkus (SmallRye GraphQL) and Python" \
     "(Strawberry) both export their code-first schema as SDL, the exports and the live" \
     "introspection conform to the canonical SDL and to each other, the canonical SDL lints" \
     "clean, and five seeded drifts fail the gate on both stacks."

# Explicit teardown in addition to the EXIT trap (belt-and-suspenders);
# compose_down is idempotent/safe to call twice.
compose_down "$COMPOSE_FILE" "$PROJECT"
