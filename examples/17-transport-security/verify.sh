#!/usr/bin/env bash
# examples/17-transport-security/verify.sh
#
# Ch17 Transport security and introspection control: both stacks serve the Chapter 13
# slice over HTTPS from framework configuration, each deployed twice from one image.
#
#   public   (hardened)   Quarkus 8270   Python 8271   introspection, suggestions, IDE, GET off
#   internal              Quarkus 8272   Python 8273   introspection on (the contract check runs here)
#
# The certificates are generated into a scratch directory at run time (gen-certs.sh) and
# are never committed. LGTM_CACERT makes every harness call trust that CA.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../_lib/lib.sh
source "$SCRIPT_DIR/../_lib/lib.sh"

PROJECT="gql-ch17-transport"
COMPOSE_FILE="$SCRIPT_DIR/compose.yaml"

SCRATCH="$(mktemp -d)"
on_exit "rm -rf '$SCRATCH'"
"$SCRIPT_DIR/gen-certs.sh" "$SCRATCH/certs"
export CERT_DIR="$SCRATCH/certs"
export LGTM_CACERT="$CERT_DIR/ca.crt"

ORIGIN="https://tracking.example.com"
EVIL="https://evil.example"

# shellcheck disable=SC2016  # GraphQL variables, not shell expansions
REGISTER='mutation($i: RegisterHandlingEventInput!) { registerHandlingEvent(input: $i) { handlingEvent { id } cargo { delivery { transportStatus } } userErrors { code } } }'
REGISTER_VARS='{"i":{"trackingId":"ABC123","type":"UNLOAD","location":"DEHAM","voyageNumber":"V100S","completionTime":"2026-10-09T15:00:00Z"}}'
# The same mutation as one JSON body, posted below with each simple content type.
FORGED_BODY="$(python3 -I -c '
import json, sys
print(json.dumps({"query": sys.argv[1], "variables": json.loads(sys.argv[2])}))
' "$REGISTER" "$REGISTER_VARS")"

# Two request bodies for the size cases, built independently of both stacks:
#   comment.json  a 100 KB comment inside a valid query (a large body, almost no tokens)
#   tokens.json   a list literal of 16000 tokens in 32 KB (under Quarkus's 64K body limit)
python3 -I -c '
import json, sys
out = sys.argv[1]
with open(out + "/comment.json", "w") as f:
    json.dump({"query": "{ __typename # " + "x" * 100000 + "\n}"}, f)
with open(out + "/tokens.json", "w") as f:
    json.dump({"query": "{ nodes(ids: [" + " ".join(["1"] * 16000) + "]) { id } }"}, f)
' "$SCRATCH"

# expect <expected> <json-path> <context> — assert one value of $resp.
expect() {
  assert_eq "$1" "$(json_field "$2" <<<"$resp")" "$stack $3"
}

# assert_curl_exit <exit-code> <context> <curl-args...> — the transport must fail with
# exactly this curl exit code (60 untrusted or wrong name, 52 plain http, 35 handshake).
# Set CURL_ERR_NEEDLE to also require that text in curl's stderr.
assert_curl_exit() {
  local want="$1" ctx="$2"; shift 2
  local rc=0 err; err="$(mktemp)"
  _lib_curl_opts; curl -sS --max-time 30 "${_LIB_CURL_OPTS[@]}" -o /dev/null "$@" 2>"$err" || rc=$?
  assert_eq "$want" "$rc" "$ctx (curl exit)"
  if [ -n "${CURL_ERR_NEEDLE:-}" ]; then
    case "$(cat "$err")" in
      *"$CURL_ERR_NEEDLE"*) echo "  ok   $ctx (curl stderr has: $CURL_ERR_NEEDLE)" ;;
      *) echo "  FAIL $ctx: curl stderr lacks '$CURL_ERR_NEEDLE': $(cat "$err")" >&2; exit 1 ;;
    esac
  fi
  rm -f "$err"
}

# json_post <url> <body> [curl-args...] — POST a JSON file or string with http_any.
# The body is sent with --data-binary; "@file" reads a file.
json_post() {
  local url="$1" body="$2"
  shift 2
  http_any POST "$url" -H 'Content-Type: application/json' --data-binary "$body" "$@"
}

# run_stack_check <stack> <pub-url> <int-url> <pub-port>
run_stack_check() {
  local stack="$1" pub="$2" int="$3" port="$4" resp out headers calls

  echo
  echo "=== verifying stack '$stack': public $pub, internal $int ==="

  wait_for_graphql "$pub"
  wait_for_graphql "$int"

  # 1. TLS works, is verified against the generated CA, and checks the name.
  resp="$(gql "$pub" '{ __typename }')"
  expect "Query" '.data.__typename' "public { __typename } over https"
  resp="$(gql "$int" '{ __typename }')"
  expect "Query" '.data.__typename' "internal { __typename } over https"
  LGTM_CACERT='' assert_curl_exit 60 "$stack without the CA the certificate is untrusted" \
    -X POST -H 'Content-Type: application/json' -d '{"query":"{ __typename }"}' "$pub"
  out="$(json_post "https://$stack:$port/graphql" '{"query":"{ __typename }"}' --resolve "$stack:$port:127.0.0.1")"
  assert_eq "200" "$(status_of "$out")" "$stack the certificate names the service ($stack is a SAN)"
  assert_curl_exit 60 "$stack a name outside the SANs fails verification" \
    --resolve "wrong.example:$port:127.0.0.1" -X POST -H 'Content-Type: application/json' \
    -d '{"query":"{ __typename }"}' "https://wrong.example:$port/graphql"
  assert_curl_exit 52 "$stack plain http to the TLS port fails" \
    -X POST -H 'Content-Type: application/json' -d '{"query":"{ __typename }"}' "http://localhost:$port/graphql"

  # 2. The protocol floor: TLS 1.3 everywhere; TLS 1.2 only on Python.
  out="$(json_post "$pub" '{"query":"{ __typename }"}' --tlsv1.3)"
  assert_eq "200" "$(status_of "$out")" "$stack accepts a TLS 1.3 client"
  case "$stack" in
    quarkus)
      CURL_ERR_NEEDLE='alert protocol version' assert_curl_exit 35 "$stack refuses a TLS 1.2 client (the TLS registry's default is TLS 1.3 only)" \
        --tlsv1.2 --tls-max 1.2 -X POST -H 'Content-Type: application/json' -d '{"query":"{ __typename }"}' "$pub"
      ;;
    python)
      out="$(json_post "$pub" '{"query":"{ __typename }"}' --tlsv1.2 --tls-max 1.2)"
      assert_eq "200" "$(status_of "$out")" "$stack accepts a TLS 1.2 client (Python's ssl floor is TLS 1.2)"
      ;;
  esac

  # 3. HSTS on every response.
  headers="$(http_headers POST "$pub" -H 'Content-Type: application/json' -d '{"query":"{ __typename }"}')"
  assert_header "$headers" strict-transport-security "max-age=31536000" "$stack HSTS"

  # 4. Introspection: refused on the public instance, open on the internal one.
  resp="$(gql "$pub" '{ __schema { queryType { name } } }')"
  assert_has_errors "$resp" "$stack public __schema is refused"
  assert_no_data "$resp" "$stack public __schema returns no data"
  local refusal
  case "$stack" in
    quarkus) refusal="Introspection has been disabled for this request" ;;
    python) refusal="introspection has been disabled" ;;
  esac
  assert_error_message_contains "$resp" "$refusal" "$stack public __schema message"
  # The root fields themselves are refused, and a real type name gets the same answer as
  # a name that does not exist.
  local resp_real resp_none
  resp_real="$(gql "$pub" '{ __type(name: "Cargo") { __typename } }')"
  resp_none="$(gql "$pub" '{ __type(name: "NoSuchType") { __typename } }')"
  assert_has_errors "$resp_real" "$stack public __type(name: \"Cargo\") is refused"
  assert_no_data "$resp_real" "$stack public __type(name: \"Cargo\") returns no data"
  assert_body_not_contains "$resp_real" "__Type" "$stack public __type names no type"
  assert_error_message_contains "$resp_real" "$refusal" "$stack public __type message"
  assert_eq "$resp_real" "$resp_none" "$stack public __type answers a real and an unknown name alike"
  # Validation still tells a known type from an unknown one: turning introspection off
  # hides the map, not every name.
  local resp_known resp_unknown
  resp_known="$(gql "$pub" '{ ... on Cargo { __typename } }')"
  resp_unknown="$(gql "$pub" '{ ... on NoSuchType { __typename } }')"
  assert_error_message_contains "$resp_known" "Cargo" "$stack a known type in a fragment gets a spread error"
  assert_error_message_contains "$resp_unknown" "Unknown type" "$stack an unknown type in a fragment gets 'Unknown type'"
  [ "$resp_known" != "$resp_unknown" ] || { echo "  FAIL $stack fragment probe answers alike" >&2; exit 1; }
  echo "  ok   $stack validation still distinguishes a known type from an unknown one"
  resp="$(gql "$pub" '{ __schema { __typename } }')"
  assert_has_errors "$resp" "$stack public __schema { __typename } is refused"
  assert_no_data "$resp" "$stack public __schema { __typename } returns no data"
  assert_body_not_contains "$resp" "__Schema" "$stack public __schema names no type"
  resp="$(gql "$pub" '{ __typename }')"
  expect "Query" '.data.__typename' "public __typename still works"
  resp="$(gql "$int" '{ __schema { queryType { name } } }')"
  assert_no_errors "$resp" "$stack internal __schema"
  expect "Query" '.data.__schema.queryType.name' "internal __schema answers"
  resp="$(gql "$int" '{ __type(name: "Cargo") { name } }')"
  expect "Cargo" '.data.__type.name' "internal __type answers"

  # 5. Suggestions: a misspelt field must not name the real one on a public instance.
  local typo='{ cargo(trackingId: "ABC123") { trackingI } }'
  resp="$(gql "$pub" "$typo")"
  assert_has_errors "$resp" "$stack public misspelt field"
  assert_body_not_contains "$resp" "Did you mean" "$stack public error offers no suggestion"
  assert_body_not_contains "$resp" "trackingId" "$stack public error names no real field"
  case "$stack" in
    quarkus) assert_error_message_contains "$resp" "Field 'trackingI' in type 'Cargo' is undefined" "$stack public misspelt field message" ;;
    python) assert_eq "Cannot query field 'trackingI' on type 'Cargo'." "$(json_field '.errors.0.message' <<<"$resp")" "$stack public misspelt field message" ;;
  esac
  resp="$(gql "$int" "$typo")"
  assert_has_errors "$resp" "$stack internal misspelt field"
  case "$stack" in
    python) assert_error_message_contains "$resp" "Did you mean 'trackingId'?" "$stack internal error suggests the field" ;;
    quarkus)
      assert_error_message_contains "$resp" "Field 'trackingI' in type 'Cargo' is undefined" "$stack internal misspelt field message"
      assert_body_not_contains "$resp" "Did you mean" "$stack graphql-java never suggests, even on the internal instance"
      ;;
  esac

  # 6. The schema document and the IDE.
  out="$(http_any GET "${pub%/graphql}/graphql/schema.graphql")"
  assert_eq "404" "$(status_of "$out")" "$stack public /graphql/schema.graphql"
  out="$(http_any GET "${int%/graphql}/graphql/schema.graphql")"
  assert_eq "404" "$(status_of "$out")" "$stack internal /graphql/schema.graphql"
  out="$(http_any GET "$pub" -H 'Accept: text/html')"
  case "$stack" in
    quarkus) assert_eq "406" "$(status_of "$out")" "$stack public GET with Accept: text/html" ;;
    python) assert_eq "404" "$(status_of "$out")" "$stack public GET with Accept: text/html" ;;
  esac
  assert_body_not_contains "$(body_of "$out")" "<html" "$stack public serves no IDE page"
  case "$stack" in
    quarkus)
      out="$(http_any GET "$int" -H 'Accept: text/html')"
      assert_eq "406" "$(status_of "$out")" "$stack internal has no IDE either (GET is off)"
      ;;
    python)
      out="$(http_any GET "$int" -H 'Accept: text/html')"
      assert_eq "200" "$(status_of "$out")" "$stack internal serves the IDE"
      assert_contains "GraphiQL" "$(body_of "$out")" "$stack internal IDE page"
      ;;
  esac

  # 7. CSRF paths. A page on another origin can send a POST with a form or text/plain
  #    Content-Type with no preflight; the body is the same JSON. Each is refused before
  #    the mutation runs, and the source-call log stays empty.
  local ctype
  for ctype in text/plain application/x-www-form-urlencoded multipart/form-data; do
    source_calls_reset "$pub"
    out="$(gql_raw "$pub" "$FORGED_BODY" application/json "$ctype")"
    case "$stack" in
      quarkus) assert_eq "415" "$(status_of "$out")" "$stack public POST as $ctype" ;;
      python) assert_eq "400" "$(status_of "$out")" "$stack public POST as $ctype" ;;
    esac
    [[ "$stack" != python ]] || assert_contains "Unsupported content type" "$(body_of "$out")" "$stack POST as $ctype: Strawberry's message"
    assert_source_call_count "$(source_calls "$pub")" '*' '*' 0 "$stack POST as $ctype: no source call, no write"
  done
  source_calls_reset "$pub"
  out="$(http_any POST "$pub" -H 'Content-Type:' --data-binary "$FORGED_BODY")"
  case "$stack" in
    quarkus) assert_eq "415" "$(status_of "$out")" "$stack public POST with the Content-Type header removed" ;;
    python) assert_eq "400" "$(status_of "$out")" "$stack public POST with the Content-Type header removed" ;;
  esac
  assert_source_call_count "$(source_calls "$pub")" '*' '*' 0 "$stack POST with no Content-Type: no write"
  # A GET cannot carry a mutation, and a public instance takes no GET query at all.
  source_calls_reset "$pub"
  out="$(gql_get "$pub" "$REGISTER" "$REGISTER_VARS")"
  case "$stack" in
    quarkus) assert_eq "405" "$(status_of "$out")" "$stack public GET mutation (GET is off)" ;;
    python) assert_eq "400" "$(status_of "$out")" "$stack public GET mutation (GET is off)" ;;
  esac
  assert_source_call_count "$(source_calls "$pub")" '*' '*' 0 "$stack GET mutation: no write"
  out="$(gql_get "$pub" '{ __typename }')"
  case "$stack" in
    quarkus) assert_eq "405" "$(status_of "$out")" "$stack public GET query is off too" ;;
    python) assert_eq "400" "$(status_of "$out")" "$stack public GET query is off too" ;;
  esac
  out="$(gql_get "$int" "$REGISTER" "$REGISTER_VARS")"
  case "$stack" in
    quarkus) assert_eq "405" "$(status_of "$out")" "$stack internal GET mutation is refused" ;;
    python) assert_eq "400" "$(status_of "$out")" "$stack internal GET mutation is refused" ;;
  esac
  # The controls for the refusals above: JSON with parameters is accepted.
  out="$(gql_raw "$pub" '{"query":"{ __typename }"}' application/json 'application/json; charset=utf-8')"
  assert_eq "200" "$(status_of "$out")" "$stack public accepts application/json; charset=utf-8"

  # 8. CORS: the one allowed origin gets its header; another origin gets none.
  headers="$(http_headers OPTIONS "$pub" -H "Origin: $ORIGIN" -H 'Access-Control-Request-Method: POST' -H 'Access-Control-Request-Headers: content-type')"
  assert_header "$headers" access-control-allow-origin "$ORIGIN" "$stack preflight from the allowed origin"
  assert_header "$headers" access-control-allow-methods "POST" "$stack preflight allows POST only"
  case "$stack" in
    quarkus) assert_header "$headers" access-control-allow-credentials "true" "$stack preflight allows credentials" ;;
    python) assert_header_absent "$headers" access-control-allow-credentials "$stack preflight allows no credentials" ;;
  esac
  out="$(http_any OPTIONS "$pub" -H "Origin: $EVIL" -H 'Access-Control-Request-Method: POST')"
  case "$stack" in
    quarkus) assert_eq "403" "$(status_of "$out")" "$stack preflight from an unknown origin" ;;
    python) assert_eq "400" "$(status_of "$out")" "$stack preflight from an unknown origin" ;;
  esac
  headers="$(http_headers OPTIONS "$pub" -H "Origin: $EVIL" -H 'Access-Control-Request-Method: POST')"
  assert_header_absent "$headers" access-control-allow-origin "$stack preflight from an unknown origin"

  source_calls_reset "$pub"
  out="$(json_post "$pub" '{"query":"{ cargo(trackingId: \"ABC123\") { trackingId } }"}' -H "Origin: $EVIL")"
  case "$stack" in
    quarkus)
      assert_eq "403" "$(status_of "$out")" "$stack actual POST from an unlisted origin"
      assert_source_call_count "$(source_calls "$pub")" '*' '*' 0 "$stack unlisted origin: no source call" ;;
    python) assert_eq "200" "$(status_of "$out")" "$stack CORSMiddleware leaves the request to the app" ;;
  esac

  # 9. Size. Quarkus bounds the body (413, before parsing; --http1.1 so the 413
  #    arrives as a plain response). On Uvicorn the
  #    body limit is set at a fronting proxy, so the 100 KB comment runs. Both bound the token count of the document.
  out="$(json_post "$pub" "@$SCRATCH/comment.json" --http1.1)"
  case "$stack" in
    quarkus) assert_eq "413" "$(status_of "$out")" "$stack a 100 KB body is refused" ;;
    python)
      assert_eq "200" "$(status_of "$out")" "$stack leaves the body limit to a fronting proxy: the 100 KB comment runs"
      resp="$(body_of "$out")"
      expect "Query" '.data.__typename' "the comment is not a token"
      ;;
  esac
  out="$(json_post "$pub" "@$SCRATCH/tokens.json" --http1.1)"
  assert_eq "200" "$(status_of "$out")" "$stack the 16000-token refusal is a 200 with errors"
  resp="$(body_of "$out")"
  assert_has_errors "$resp" "$stack a 16000-token document is refused"
  case "$stack" in
    quarkus) assert_error_message_contains "$resp" "Unparseable input document" "$stack token limit (graphql-java's default of 15000)" ;;
    python) assert_error_message_contains "$resp" "Document contains more than 5000 tokens" "$stack token limit (MaxTokensLimiter, 5000)" ;;
  esac

  # 10. Errors stay masked over TLS (Chapter 9): the booking fault keeps its code and
  #     the message the allowlist exposes.
  resp="$(gql "$pub" '{ cargo(trackingId: "GHI345") { trackingId } }')"
  assert_error_extension "$resp" '["cargo"]' code '"SERVICE_UNAVAILABLE"' "$stack public GHI345 keeps its code"
  assert_error_message_at "$resp" '["cargo"]' "booking service unavailable" "$stack public GHI345 message"

  # 11. A write over TLS on the public instance, once the refusals are done: the
  #     controls above were refused for their Content-Type, not for the mutation.
  resp="$(gql "$pub" "$REGISTER" "$REGISTER_VARS")"
  assert_no_errors "$resp" "$stack public mutation as application/json"
  expect "evt_10" '.data.registerHandlingEvent.handlingEvent.id' "the first write is evt_10: the refused attempts wrote nothing"

  # 12. The contract is checked against the internal instance. The deprecation, the
  #     scalars and the whole slice come from there.
  assert_deprecated "$int" Itinerary finalArrivalDate "Use \`finalArrivalTime\`." "$stack Itinerary.finalArrivalDate"
  assert_not_deprecated "$int" Itinerary finalArrivalTime "$stack Itinerary.finalArrivalTime"
  local scalar
  for scalar in TrackingId UnLocode DateTime; do
    # shellcheck disable=SC2016
    resp="$(gql "$int" 'query Kind($n: String!) { __type(name: $n) { kind specifiedByURL } }' "{\"n\":\"$scalar\"}")"
    assert_no_errors "$resp" "$stack $scalar introspection"
    expect "SCALAR" '.data.__type.kind' "$scalar kind"
    case "$scalar" in
      UnLocode) expect "https://unece.org/trade/uncefact/unlocode" '.data.__type.specifiedByURL' "$scalar specifiedByURL" ;;
      DateTime) expect "https://www.rfc-editor.org/rfc/rfc3339" '.data.__type.specifiedByURL' "$scalar specifiedByURL" ;;
      *) assert_null_at "$resp" '.data.__type.specifiedByURL' "$stack $scalar has no specifiedByURL" ;;
    esac
  done
  assert_sdl_conforms "$int" "$stack internal schema vs contracts/schema"
  local sdl_rev sdl_removed
  sdl_rev="$(_sdl_diff "$CANONICAL_SDL_GLOB" "$int")"
  sdl_removed="$(grep '✖' <<<"$sdl_rev" | grep -vE "$LGTM_SDL_IGNORE" | sed -E 's/^.*✖ +//' | sort || true)"
  assert_eq "Schema subscription type Subscription was removed.
Type Subscription was removed" "$sdl_removed" "$stack only Subscription is unserved"

  echo "=== $stack: transport and introspection checks passed ==="
}

echo "=== Step 1: docker compose up ==="
compose_up "$COMPOSE_FILE" "$PROJECT"

echo
echo "=== Step 2: verify both stacks ==="
run_stack_check "quarkus" "https://localhost:8270/graphql" "https://localhost:8272/graphql" 8270
run_stack_check "python" "https://localhost:8271/graphql" "https://localhost:8273/graphql" 8271

echo
echo "PASS - Ch17 Transport security and introspection control: Quarkus (TLS registry, TLS 1.3 only)" \
     "and Python (uvicorn, TLS 1.2 and up) serve the tracking view over HTTPS with a generated CA," \
     "send HSTS, refuse introspection, field suggestions, the IDE and GET on the public instances," \
     "refuse form and text/plain POSTs without running them, answer CORS for one origin, bound the" \
     "request, keep errors masked, and conform to the canonical SDL (except Subscription) on the" \
     "internal instances."
