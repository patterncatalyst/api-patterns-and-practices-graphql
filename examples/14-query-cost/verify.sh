#!/usr/bin/env bash
# examples/14-query-cost/verify.sh
#
# Ch14 Depth limits and query cost analysis: a client chooses the shape of a
# query, so the server bounds the shape before it runs. Each stack applies its
# own depth and token limits and an alias limit of 20 with the same message;
# both apply one list-aware cost budget of 1000, with the same formula and the
# same message, so a query costs the same number of units on SmallRye
# (graphql-java's MaxQueryComplexityInstrumentation with a
# FieldComplexityCalculator) and on Strawberry (a SchemaExtension that runs
# before execution).
#
#   cost(field) = 0                              for __* fields
#   cost(field) = 1 + m * sum(cost(children))    otherwise
#   m = first, else last, else 10 on cargos and handlingHistory;
#       len(ids) on nodes; 1 elsewhere.
#
# Every rejection is checked against the source-call log: a refused request makes
# no source call at all.
#
# The queries are defined once, here. The long ones (150 aliases, 1000 ids, 6000
# tokens) are generated with python3 -I.
#
# cost(field) is clamped to 2,147,483,647 / 5000 = 429496 on both stacks: a
# document of at most 5000 tokens has at most 5000 fields, so the sum of any
# siblings stays within the 32-bit range. No total below 429496 changes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../_lib/lib.sh
source "$SCRIPT_DIR/../_lib/lib.sh"

PROJECT="gql-ch14-query-cost"
COMPOSE_FILE="$SCRIPT_DIR/compose.yaml"
BUDGET=1000

# Chapter 13's four-cargo page. Cost 53.
Q_FAN='{ cargos(first: 4) { edges { node { trackingId itinerary { legs { voyage { number } loadLocation { unLocode } unloadLocation { unLocode } } } delivery { transportStatus } } } } }'
# Chapter 1's nested query: eleven fields deep, 300 bytes. Cost 385151.
Q_CH1='{ cargos(first: 50) { edges { node { handlingHistory(first: 50) { edges { node { cargo { handlingHistory(first: 50) { edges { node { id } } } } } } } } } } }'
# One level less: cost 7651.
Q_WIDE_COST='{ cargos(first: 50) { edges { node { handlingHistory(first: 50) { edges { node { id } } } } } } }'
# Sixteen fields deep with first: 1 throughout: cost 16. Its fifteen-deep prefix costs 15.
D_DEEP='{ cargos(first: 1) { edges { node { handlingHistory(first: 1) { edges { node { cargo { handlingHistory(first: 1) { edges { node { cargo { handlingHistory(first: 1) { edges { node { cargo { trackingId } } } } } } } } } } } } } } } }'
D_OK='{ cargos(first: 1) { edges { node { handlingHistory(first: 1) { edges { node { cargo { handlingHistory(first: 1) { edges { node { cargo { handlingHistory(first: 1) { edges { node { id } } } } } } } } } } } } } } }'
# shellcheck disable=SC2016  # GraphQL variables, not shell expansions
Q_VARS='query($n: Int) { cargos(first: $n) { edges { node { handlingHistory(first: $n) { edges { node { id } } } } } } }'
# A fragment that carries a page of events.
F_HISTORY='fragment F on Cargo { handlingHistory(first: 50) { edges { node { id } } } }'

# q_edge <n> — Q_WIDE_COST with handlingHistory(first: n); cost 151 + 150 n.
q_edge() {
  printf '{ cargos(first: 50) { edges { node { handlingHistory(first: %s) { edges { node { id } } } } } } }' "$1"
}

# gen_alias_bomb — 150 aliases of one cargo lookup, 7 fields each.
gen_alias_bomb() {
  python3 -I -c '
print("{ " + " ".join(
    f"a{k}: cargo(trackingId: \"ABC123\") {{ delivery {{ transportStatus }} itinerary {{ legs {{ voyage {{ number }} }} }} }}"
    for k in range(150)) + " }")'
}

# nodes_tail <n> — a `nodes` field over n ids, which costs 1 + n; empty for 0.
# Appended to a document, it pushes a priced fragment over the budget so the
# message shows the fragment's price.
nodes_tail() {
  python3 -I -c '
import sys
n = int(sys.argv[1])
print(" nodes(ids: [" + ", ".join(["\"loc_NLRTM\""] * n) + "]) { id }" if n else "", end="")' "$1"
}

# gen_fragments [n] — the fragment case: fragment definitions F0..F10 spread from
# one cargo selection, optionally followed by nodes over n ids.
gen_fragments() {
  python3 -I -c '
import sys
parts = ["fragment F0 on Cargo { trackingId }"]
parts += [f"fragment F{k} on Cargo {{ ...F{k-1} ...F{k-1} }}" for k in range(1, 11)]
parts.append("{ cargo(trackingId: \"ABC123\") { ...F10 }" + sys.argv[1] + " }")
print(" ".join(parts))' "$(nodes_tail "${1:-0}")"
}

# gen_f_nest [n] — the F_NEST document.
gen_f_nest() {
  python3 -I -c '
import sys
n = int(sys.argv[1])
parts = ["fragment F0 on Cargo { a: trackingId }"]
for k in range(1, n + 1):
    parts.append("fragment F%d on Cargo { ...F%d ...F%d }" % (k, k - 1, k - 1))
parts.append("{ cargo(trackingId: \"ABC123\") { ...F%d } }" % n)
print(" ".join(parts))' "${1:-24}"
}

# gen_reuse <aliases> [n] — the same fragment spread under that many cargo
# aliases, optionally followed by nodes over n ids.
gen_reuse() {
  python3 -I -c '
import sys
n = int(sys.argv[1])
print("fragment F on Cargo { handlingHistory(first: 50) { edges { node { id } } } } { " + " ".join(
    f"a{k}: cargo(trackingId: \"ABC123\") {{ ...F }}" for k in range(n)) + sys.argv[2] + " }")' "$1" "$(nodes_tail "${2:-0}")"
}

# gen_ids <n> — nodes over n copies of one id. Cost 1 + n.
gen_ids() {
  python3 -I -c 'import sys; print("{ nodes(ids: [" + ", ".join(["\"loc_NLRTM\""] * int(sys.argv[1])) + "]) { id } }")' "$1"
}

# gen_aliased_chains — two aliased copies of cargos(first: 50) with three nested
# handlingHistory(first: 50) pages and 400 id-aliases at the leaf: about 6.5 KB,
# 802 aliases, under the depth limit and the token limit.
gen_aliased_chains() {
  python3 -I -c '
ids = " ".join(f"i{k}: id" for k in range(400))
chain = "cargos(first: 50) { edges { node { handlingHistory(first: 50) { edges { node { cargo { handlingHistory(first: 50) { edges { node { cargo { handlingHistory(first: 50) { edges { node { " + ids + " } } } } } } } } } } } } } }"
print("{ a: " + chain + " b: " + chain + " }")'
}

# gen_clamp — two aliased copies with pages of 5000 at three levels. Each copy
# is far above the clamp, so the total is 2 x 429496.
gen_clamp() {
  python3 -I -c '
chain = "cargos(first: 5000) { edges { node { handlingHistory(first: 5000) { edges { node { cargo { handlingHistory(first: 5000) { edges { node { id } } } } } } } } } }"
print("{ a: " + chain + " b: " + chain + " }")'
}

# gen_alias_fragment — an 11-alias fragment spread twice: 22 aliased fields once expanded.
gen_alias_fragment() {
  python3 -I -c '
fields = " ".join(f"k{k}: trackingId" for k in range(11))
print("fragment F on Cargo { " + fields + " } { cargo(trackingId: \"ABC123\") { ...F } c: cargo(trackingId: \"ABC123\") { ...F } }")'
}

# gen_flood — 6000 __typename selections: 6,002 tokens, 60 KB of text.
gen_flood() {
  python3 -I -c 'print("{ " + "__typename " * 6000 + "}")'
}

# expect <expected> <json-path> <context> — assert one value of $resp.
expect() {
  assert_eq "$1" "$(json_field "$2" <<<"$resp")" "$stack $3"
}

# expect_json <expected-json> <json-path> <context>
expect_json() {
  assert_json_eq "$1" "$(json_field "$2" <<<"$resp")" "$stack $3"
}

# reject <label> <expected-message> <query> [variables-json] — the request is
# refused with this message, no data, and not one source call.
reject() {
  local label="$1" message="$2" query="$3" variables="${4:-}"
  source_calls_reset "$url"
  resp="$(gql "$url" "$query" "$variables")"
  assert_has_errors "$resp" "$stack $label"
  assert_no_data "$resp" "$stack $label: no data"
  expect "$message" '.errors.0.message' "$label: message"
  assert_source_call_count "$(source_calls "$url")" '*' '*' 0 "$stack $label: rejected before any source call"
}

# cost_message <cost> — graphql-java's text, which the Python extension repeats.
cost_message() {
  printf 'maximum query complexity exceeded %s > %s' "$1" "$BUDGET"
}

# run_stack_check <stack> <url>
run_stack_check() {
  local stack="$1" url="$2" resp calls total status ctype

  echo
  echo "=== verifying stack '$stack' at $url ==="

  wait_for_graphql "$url"

  # 1. Legitimate traffic still runs: Chapter 13's page, in Chapter 13's calls.
  source_calls_reset "$url"
  resp="$(gql "$url" "$Q_FAN")"
  assert_no_errors "$resp" "$stack Q_FAN"
  assert_json_eq '["VWX901","XYZ789","STU678","DEF456"]' \
    "$(python3 -I -c 'import json, sys; print(json.dumps([e["node"]["trackingId"] for e in json.load(sys.stdin)["data"]["cargos"]["edges"]]))' <<<"$resp")" \
    "$stack Q_FAN pages the four cargos of Chapter 13"
  case "$stack" in
    python) total=6 ;;
    quarkus) total=8 ;;
  esac
  assert_source_call_count "$(source_calls "$url")" '*' '*' "$total" "$stack Q_FAN: $total source calls, as in Chapter 13"
  resp="$(gql "$url" '{ __typename }')"
  assert_no_errors "$resp" "$stack __typename"
  expect "Query" '.data.__typename' "__typename"
  # Introspection stays under every limit (assert_sdl_conforms below reads the
  # whole schema through it).

  # 2. Shallow but expensive: the amplification is in the page sizes, not the depth.
  reject "Q_CH1" "$(cost_message 385151)" "$Q_CH1"
  reject "Q_WIDE_COST" "$(cost_message 7651)" "$Q_WIDE_COST"

  # 3. Deep but cheap: depth 16 costs 16 units and is refused by the depth limit;
  #    depth 15 runs. graphql-java counts a root field as depth 1 and Strawberry
  #    as 0, so the limits are 15 and 14 and refuse the same documents.
  case "$stack" in
    quarkus) reject "D_DEEP" "maximum query depth exceeded 16 > 15" "$D_DEEP" ;;
    python) reject "D_DEEP" "'anonymous' exceeds maximum operation depth of 14" "$D_DEEP" ;;
  esac
  resp="$(gql "$url" "$D_OK")"
  assert_no_errors "$resp" "$stack the 15-deep prefix of D_DEEP runs"

  # 4. The boundary of the budget: 151 + 150 n.
  #    The page holds the whole seed, GHI345 included, so the booking outage of
  #    Chapter 9 shows in the response; what matters here is that the budget admits
  #    the query and every edge is returned.
  source_calls_reset "$url"
  resp="$(gql "$url" "$(q_edge 5)")"
  assert_body_not_contains "$resp" "maximum query complexity" "$stack Q_EDGE(5): cost 901 is within the budget"
  assert_eq "6" "$(json_len .data.cargos.edges <<<"$resp")" "$stack Q_EDGE(5) returns the whole seed"
  reject "Q_EDGE(6)" "$(cost_message 1051)" "$(q_edge 6)"

  # 5. Aliases. Both stacks count aliased fields and refuse more than 20 with
  #    the same words; the count follows fragment spreads (a spread counts again
  #    wherever it appears) and ignores @skip on both stacks.
  reject "A_BOMB" "150 aliases found. Allowed: 20" "$(gen_alias_bomb)"
  reject "A_FRAG" "23 aliases found. Allowed: 20" "$(gen_alias_fragment)"
  #    The alias limit is checked before the cost, so a document of 802 aliases
  #    is refused by it on both stacks.
  reject "A_CHAINS" "802 aliases found. Allowed: 20" "$(gen_aliased_chains)"
  #    With two aliases the cost clamp is what states the total: each copy is
  #    capped at 429496 and the total is 858992 on both stacks.
  reject "C_CLAMP" "$(cost_message 858992)" "$(gen_clamp)"

  # 6. Fragments. Both analysers price a fragment definition where it is first
  #    spread and not again. The F_FAN case is priced 2 (the cargo field and
  #    trackingId) and runs once.
  source_calls_reset "$url"
  resp="$(gql "$url" "$(gen_fragments)")"
  assert_no_errors "$resp" "$stack F_FAN: fragment case priced 2 and runs"
  expect "ABC123" '.data.cargo.trackingId' "F_FAN trackingId"
  assert_source_call_count "$(source_calls "$url")" booking getCargo 1 "$stack F_FAN: fragment case runs once"
  #    The price of a reused fragment is the price of its first spread: eight
  #    aliases of a 152-unit lookup are priced at 152 + 7 and run as eight reads.
  source_calls_reset "$url"
  resp="$(gql "$url" "$(gen_reuse 8)")"
  assert_no_errors "$resp" "$stack F_REUSE: eight spreads of one fragment pass the budget"
  assert_source_call_count "$(source_calls "$url")" handling pageEvents 8 "$stack F_REUSE: the fragment's page of events is read eight times"
  #    The prices 2 and 159 are asserted by adding a field of known cost to push each
  #    over the budget: nodes over n ids costs 1 + n.
  reject "F_FAN priced 2" "$(cost_message 1002)" "$(gen_fragments 999)"
  reject "F_REUSE priced 159" "$(cost_message 1002)" "$(gen_reuse 8 842)"
  #    Two spreads under list fields show the same rule in a refused price.
  reject "F_REUSE under two pages" "$(cost_message 7752)" \
    "$F_HISTORY { a: cargos(first: 50) { edges { node { ...F } } } b: cargos(first: 50) { edges { node { ...F } } } }"

  #    F_REUSE_PAGE: a fragment spread at the root and again under a page is priced 253.
  reject "F_REUSE_PAGE priced 253" "$(cost_message 1001)" \
    "$F_HISTORY { cargo(trackingId: \"ABC123\") { ...F } cargos(first: 50) { edges { node { ...F } } }$(nodes_tail 747) }"

  # 6a. F_NEST is refused by the alias limit.
  source_calls_reset "$url"
  resp="$(gql "$url" "$(gen_f_nest 25)")"
  assert_has_errors "$resp" "$stack F_NEST"
  assert_error_message_contains "$resp" "aliases found. Allowed: 20" "$stack F_NEST: refused by the alias limit"
  assert_source_call_count "$(source_calls "$url")" '*' '*' 0 "$stack F_NEST: refused by the alias limit, 0 source calls"

  # 6b. @skip and @include. A skipped field or spread is not priced, and a skipped
  #     spread does not mark its fragment as counted: the live spread below it is
  #     priced (1 + 7651 = 7652), as graphql-java prices it. A skipped page
  #     costs nothing, so the query runs.
  reject "F_SKIP" "$(cost_message 7652)" \
    "$F_HISTORY { x: cargo(trackingId: \"ABC123\") { ...F @skip(if: true) } cargos(first: 50) { edges { node { ...F } } } }"
  source_calls_reset "$url"
  resp="$(gql "$url" '{ cargos(first: 50) @skip(if: true) { edges { node { handlingHistory(first: 50) { edges { node { id } } } } } } __typename }')"
  assert_no_errors "$resp" "$stack S_FIELD: a skipped page is not priced"
  expect "Query" '.data.__typename' "S_FIELD __typename"
  assert_source_call_count "$(source_calls "$url")" '*' '*' 0 "$stack S_FIELD: the skipped field makes no source call"

  # 7. Huge pages. first: 5000 is priced; first: 51 is within the budget (154)
  #    and refused by Chapter 12's cap in the resolver, before any source call.
  reject "first: 5000" "$(cost_message 15001)" '{ cargos(first: 5000) { edges { node { trackingId } } } }'
  source_calls_reset "$url"
  resp="$(gql "$url" '{ cargos(first: 51) { edges { node { trackingId } } } }')"
  assert_error_shape "$resp" execution "$stack first: 51"
  assert_error_extension "$resp" '["cargos"]' code '"BAD_USER_INPUT"' "$stack first: 51: code"
  assert_error_message_at "$resp" '["cargos"]' "first must be between 0 and 50" "$stack first: 51: message"
  assert_null_at "$resp" '.data' "$stack first: 51: data is null"
  assert_source_call_count "$(source_calls "$url")" '*' '*' 0 "$stack first: 51: refused before any source call"
  #    A negative page size counts as 0: it cannot offset another field's price.
  reject "first: -1000 beside a page" "$(cost_message 7652)" \
    '{ a: cargos(first: -1000) { edges { node { trackingId } } } b: cargos(first: 50) { edges { node { handlingHistory(first: 50) { edges { node { id } } } } } } }'

  # 8. nodes is bounded by its cost: 1000 ids are refused, one id runs.
  reject "N_IDS" "$(cost_message 1001)" "$(gen_ids 1000)"
  resp="$(gql "$url" '{ nodes(ids: ["loc_NLRTM"]) { id } }')"
  assert_no_errors "$resp" "$stack nodes with one id"
  expect_json '[{"id":"loc_NLRTM"}]' '.data.nodes' "nodes returns the one object"

  # 9. A token flood is refused by the parser. Strawberry reports the limit;
  #    SmallRye answers with its generic parse failure.
  source_calls_reset "$url"
  resp="$(gql "$url" "$(gen_flood)")"
  assert_has_errors "$resp" "$stack T_FLOOD"
  assert_no_data "$resp" "$stack T_FLOOD: no data"
  case "$stack" in
    python) assert_error_message_contains "$resp" "Document contains more than 5000 tokens" "$stack T_FLOOD: the parser's limit" ;;
    quarkus) expect "Unparseable input document" '.errors.0.message' "T_FLOOD: SmallRye's parse failure" ;;
  esac
  assert_source_call_count "$(source_calls "$url")" '*' '*' 0 "$stack T_FLOOD: rejected before any source call"

  # 10. A batch array. Strawberry's batching is off: 400. SmallRye reads one JSON
  #     object and answers an error without data.
  source_calls_reset "$url"
  resp="$(gql_raw "$url" '[{"query":"{ __typename }"},{"query":"{ __typename }"}]')"
  status="$(status_of "$resp")"
  resp="$(body_of "$resp")"
  ctype="$(curl -sS -o /dev/null -w '%{content_type}' -X POST -H 'Content-Type: application/json' \
    -d '[{"query":"{ __typename }"}]' "$url")"
  case "$stack" in
    python)
      assert_eq "400" "$status" "$stack B_ARRAY: status"
      assert_eq "text/plain; charset=utf-8" "$ctype" "$stack B_ARRAY: content type"
      assert_contains "Batching is not enabled" "$resp" "$stack B_ARRAY: body"
      ;;
    quarkus)
      assert_eq "200" "$status" "$stack B_ARRAY: status"
      assert_eq "application/graphql-response+json; charset=UTF-8" "$ctype" "$stack B_ARRAY: content type"
      assert_no_data "$resp" "$stack B_ARRAY: no data"
      expect "Unparseable request" '.errors.0.message' "B_ARRAY: SmallRye refuses an array"
      ;;
  esac
  assert_source_call_count "$(source_calls "$url")" '*' '*' 0 "$stack B_ARRAY: no source call"

  # 11. Variables are priced: the extension runs after variable coercion on
  #     Strawberry, and the calculator reads the resolved arguments on SmallRye.
  reject "variables n=50" "$(cost_message 7651)" "$Q_VARS" '{"n":50}'
  resp="$(gql "$url" "$Q_VARS" '{"n":2}')"
  assert_no_errors "$resp" "$stack variables n=2: cost 1 + 2 x (3 + 3 x 2) = 19"
  #     Introspection is free: the whole schema is read under a budget of 1000.
  resp="$(gql "$url" '{ __schema { types { name fields { name args { name type { kind ofType { kind name } } } } } } }')"
  assert_no_errors "$resp" "$stack introspection costs 0"

  # 12. The deprecation of Chapter 11, the custom scalars, and the live schema:
  #     limits change no field, argument or nullability.
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

  echo "=== $stack: query cost check passed ==="
}

echo "=== Step 1: docker compose up ==="
compose_up "$COMPOSE_FILE" "$PROJECT"

echo
echo "=== Step 2: verify both stacks ==="
run_stack_check "quarkus" "http://localhost:8240/graphql"
run_stack_check "python" "http://localhost:8241/graphql"

echo
echo "PASS - Ch14 Depth limits and query cost analysis: Quarkus (SmallRye depth limit, an alias-count" \
     "instrumentation and graphql-java's complexity instrumentation with a list-aware calculator) and" \
     "Python (depth and alias validation rules, Strawberry's token limiter and a cost extension) price the same queries identically against a budget of 1000, refuse" \
     "deep, wide, aliased, oversized, flooded and batched requests before any source call (a fragment case is priced and runs once), let" \
     "introspection through, and still conform to the canonical SDL except for Subscription."
