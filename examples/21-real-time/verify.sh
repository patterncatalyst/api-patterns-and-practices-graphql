#!/usr/bin/env bash
# examples/21-real-time/verify.sh
#
# Ch21 Real-time: Subscription.cargoHandled over WebSocket, GraphQL over SSE,
# and a plain SSE feed with Last-Event-ID resume.
#
# The subscription client is a small Python script on gql[websockets]
# (client/subscribe.py), run on the compose network with `compose_run`. The
# servers carry no protocol code of their own: SmallRye GraphQL and Strawberry
# speak graphql-transport-ws (and the older graphql-ws), Strawberry also speaks
# graphql-sse, and each stack serves the plain SSE feed with its REST framework.
#
# Every mutation is gated on /debug/subscribers, so the subscription exists
# before the event it must receive, and every subscription test ends with the
# count back at 0. Handling state carries forward on ABC123, in this order:
# evt_10 (REG_A1), evt_12 (REG_A2), then one filler event per later case.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../_lib/lib.sh
source "$SCRIPT_DIR/../_lib/lib.sh"

# assert_sdl_equals diffs the two schemas in both directions. A deprecation reaches
# the live side as state (isDeprecated and deprecationReason) and the canonical
# file declares it as a directive, so the diff names the directive on that one
# field. The state itself is asserted below with assert_deprecated.
LGTM_SDL_IGNORE="${LGTM_SDL_IGNORE}|Directive deprecated was (removed from|added to) field Itinerary\.finalArrivalDate\$"

PROJECT="gql-ch21-real-time"
COMPOSE_FILE="$SCRIPT_DIR/compose.yaml"

SCRATCH="$(mktemp -d)"
on_exit 'rm -rf "$SCRATCH"'

# shellcheck disable=SC2016  # GraphQL variables, not shell expansions
REGISTER='mutation($i: RegisterHandlingEventInput!) { registerHandlingEvent(input: $i) { handlingEvent { id } userErrors { code } } }'
# shellcheck disable=SC2016
SUB_BODY='{"query":"subscription Watch($id: TrackingId!) { cargoHandled(trackingId: $id) { id type location { name } cargo { trackingId delivery { transportStatus } } } }","variables":{"id":"ABC123"}}'

REG_A1='{"trackingId":"ABC123","type":"UNLOAD","location":"DEHAM","voyageNumber":"V100S","completionTime":"2026-10-09T15:00:00Z"}'
REG_D1='{"trackingId":"DEF456","type":"CUSTOMS","location":"NLRTM","completionTime":"2026-10-09T16:00:00Z"}'
REG_A2='{"trackingId":"ABC123","type":"LOAD","location":"DEHAM","voyageNumber":"V100S","completionTime":"2026-10-09T18:00:00Z"}'

# register <url> <input-json> — run the mutation, print the new event id.
register() {
  local resp
  resp="$(gql "$1" "$REGISTER" "{\"i\":$2}")" || return 1
  assert_no_errors "$resp" "$stack registerHandlingEvent" || return 1
  assert_json_eq '[]' "$(json_field '.data.registerHandlingEvent.userErrors' <<<"$resp")" "$stack registration has no userErrors" || return 1
  json_field '.data.registerHandlingEvent.handlingEvent.id' <<<"$resp"
}

# filler <url> <hour> — a CUSTOMS event for ABC123: a registration that is only
# there to be heard.
filler() {
  register "$1" "{\"trackingId\":\"ABC123\",\"type\":\"CUSTOMS\",\"location\":\"DEHAM\",\"completionTime\":\"2026-10-09T$2:00:00Z\"}"
}

# wait_for_lines <file> <n> [timeout] — until the file holds n lines.
wait_for_lines() {
  local file="$1" want="$2" timeout="${3:-30}" waited=0 have=0
  while ((waited < timeout)); do
    have="$(wc -l <"$file")"
    if ((have >= want)); then return 0; fi
    sleep 1
    waited=$((waited + 1))
  done
  echo "verify: FAIL - $file held $have lines after ${timeout}s, wanted $want" >&2
  return 1
}

# nth_line <file> <n> — the n-th line (1-based).
nth_line() {
  sed -n "${2}p" "$1"
}

# frame_types <stderr-file> [last] — the frames the client logged, as "<dir> <type>"
# in a JSON list, up to and including the first frame named "last" when given.
frame_types() {
  python3 -I -c '
import json, sys
out = []
for line in open(sys.argv[1]):
    direction, _, body = line.partition(" ")
    if direction in (">>>", "<<<") and json.loads(body)["type"] not in ("ping", "pong"):
        out.append("%s %s" % (direction, json.loads(body)["type"]))
        if out[-1] == (sys.argv[2] if len(sys.argv) > 2 else None):
            break
print(json.dumps(out))
' "$@"
}

# event_ids <file> — the ids of the events a client printed, in order, as a JSON list.
event_ids() {
  python3 -I -c '
import json, sys
print(json.dumps([json.loads(l)["cargoHandled"]["id"] for l in open(sys.argv[1]) if l.strip()]))
' "$1"
}

# gqlsse_ids <events-file> — the cargoHandled ids carried by graphql-sse "next" events, as a JSON list.
gqlsse_ids() {
  python3 -I -c '
import json, sys
events = (json.loads(l) for l in open(sys.argv[1]) if l.strip())
print(json.dumps([json.loads(e["data"])["data"]["cargoHandled"]["id"] for e in events if e["event"] == "next"]))
' "$1"
}

# sse_ids <events-file> — the ids of the SSE events collected, as a JSON list.
sse_ids() {
  python3 -I -c '
import json, sys
print(json.dumps([json.loads(l)["id"] for l in open(sys.argv[1]) if l.strip()]))
' "$1"
}

# subscribers <base> <channel> <tracking-id> — the live subscription count (0 when none was ever seen).
subscribers() {
  python3 -I -c '
import json, sys
print(json.load(sys.stdin).get(sys.argv[1], {}).get(sys.argv[2], 0))
' "$2" "$3" < <(curl -fsS --max-time 5 -H 'Accept: application/json' "$1/debug/subscribers")
}

# only_ops <calls-json> <op,...> — the calls of a log whose op is in the list, as a log.
only_ops() {
  python3 -I -c '
import json, sys
ops = set(sys.argv[1].split(","))
print(json.dumps({"calls": [c for c in json.load(sys.stdin)["calls"] if c["op"] in ops]}))
' "$2" <<<"$1"
}

# run_stack_check <stack> <port>
run_stack_check() {
  local stack="$1" port="$2"
  local url="http://localhost:$port/graphql" base="http://localhost:$port"
  local ws="ws://$stack:8080/graphql"
  local resp calls out err pid id1 id2 id_d1 hdr data expected_json rc scalar
  local -a abc_ids=()

  echo
  echo "=== verifying stack '$stack' at $url ==="

  wait_for_graphql "$url"

  # 1. The whole canonical SDL is served, Subscription included.
  assert_sdl_equals "$url" "$stack schema equals the canonical SDL"
  resp="$(gql "$url" '{ __schema { subscriptionType { name } } }')"
  assert_eq "Subscription" "$(json_field '.data.__schema.subscriptionType.name' <<<"$resp")" "$stack subscription root type"
  assert_deprecated "$url" Itinerary finalArrivalDate "Use \`finalArrivalTime\`." "$stack Itinerary.finalArrivalDate"
  assert_not_deprecated "$url" Itinerary finalArrivalTime "$stack Itinerary.finalArrivalTime"
  for scalar in TrackingId UnLocode DateTime; do
    # shellcheck disable=SC2016
    resp="$(gql "$url" 'query Kind($n: String!) { __type(name: $n) { kind specifiedByURL } }' "{\"n\":\"$scalar\"}")"
    assert_eq "SCALAR" "$(json_field '.data.__type.kind' <<<"$resp")" "$stack $scalar kind"
    case "$scalar" in
      UnLocode) assert_eq "https://unece.org/trade/uncefact/unlocode" "$(json_field '.data.__type.specifiedByURL' <<<"$resp")" "$stack $scalar specifiedByURL" ;;
      DateTime) assert_eq "https://www.rfc-editor.org/rfc/rfc3339" "$(json_field '.data.__type.specifiedByURL' <<<"$resp")" "$stack $scalar specifiedByURL" ;;
      *) assert_null_at "$resp" '.data.__type.specifiedByURL' "$stack $scalar has no specifiedByURL" ;;
    esac
  done
  assert_json_eq '{"graphql":{},"sse":{}}' "$(curl -fsS "$base/debug/subscribers")" "$stack no subscriber before the first subscription"

  # 2. A subscription that selects a field the contract lacks is refused before
  #    it runs: an error frame naming the field, and no subscriber.
  out="$SCRATCH/$stack-invalid.out"
  rc=0
  compose_run client --url "$ws" --count 1 --timeout 20 --query /app/fixtures/invalid-field.graphql >"$out" 2>"$SCRATCH/$stack-invalid.err" || rc=$?
  assert_eq "1" "$rc" "$stack invalid subscription exits 1"
  assert_contains "weight" "$(<"$out")" "$stack the error frame names the field"
  assert_contains '"error"' "$(<"$out")" "$stack the client prints an error"
  assert_eq "0" "$(subscribers "$base" graphql ABC123)" "$stack no subscriber was registered for the invalid document"

  # 3. graphql-transport-ws: two events for ABC123, in order, none for DEF456.
  #    The client starts, the subscriber count gates the first mutation, and the
  #    client's output gates the next one, so each event is read before the
  #    following registration.
  source_calls_reset "$url"
  out="$SCRATCH/$stack-ws.out"
  err="$SCRATCH/$stack-ws.err"
  : >"$out"
  compose_run client --url "$ws" --subprotocol graphql-transport-ws --tracking-id ABC123 --count 2 --timeout 60 --frames >"$out" 2>"$err" &
  pid=$!
  wait_for_json "$base/debug/subscribers" '.graphql.ABC123' 1 60
  id1="$(register "$url" "$REG_A1")"
  assert_eq "evt_10" "$id1" "$stack REG_A1 is evt_10"
  abc_ids+=("$id1")
  wait_for_lines "$out" 1 30
  id_d1="$(register "$url" "$REG_D1")"
  assert_eq "evt_11" "$id_d1" "$stack REG_D1 is evt_11, a different cargo"
  id2="$(register "$url" "$REG_A2")"
  assert_eq "evt_12" "$id2" "$stack REG_A2 is evt_12"
  abc_ids+=("$id2")
  rc=0
  wait "$pid" || rc=$?
  assert_eq "0" "$rc" "$stack the client received its two events"
  assert_json_eq '["evt_10","evt_12"]' "$(event_ids "$out")" "$stack two events, in order, none from DEF456"
  assert_eq "Hamburg" "$(json_field '.cargoHandled.location.name' <<<"$(nth_line "$out" 1)")" "$stack event 1 location"
  assert_eq "Hamburg" "$(json_field '.cargoHandled.location.name' <<<"$(nth_line "$out" 2)")" "$stack event 2 location"
  assert_eq "IN_PORT" "$(json_field '.cargoHandled.cargo.delivery.transportStatus' <<<"$(nth_line "$out" 1)")" "$stack event 1 delivery"
  assert_eq "ONBOARD_CARRIER" "$(json_field '.cargoHandled.cargo.delivery.transportStatus' <<<"$(nth_line "$out" 2)")" "$stack event 2 delivery, read afresh"
  assert_eq "ABC123" "$(json_field '.cargoHandled.cargo.trackingId' <<<"$(nth_line "$out" 2)")" "$stack event 2 cargo"
  assert_json_eq '[">>> connection_init","<<< connection_ack",">>> subscribe","<<< next","<<< next",">>> complete"]' \
    "$(frame_types "$err")" "$stack the graphql-transport-ws frames of the run"

  # 4. One execution per event. The subscription's own calls are the bulk
  #    reads; the registrations make single-key calls. Two events make two of
  #    each bulk read, under one request id for the subscription.
  calls="$(source_calls "$url")"
  assert_source_call_count "$calls" booking getCargos 2 "$stack HandlingEvent.cargo: one read per event"
  assert_source_call_count "$calls" location getLocations 2 "$stack HandlingEvent.location: one read per event"
  assert_source_call_count "$calls" routing getItineraries 2 "$stack Cargo.delivery reads the itinerary per event"
  assert_source_call_count "$calls" handling listEventsFor 2 "$stack Cargo.delivery reads the handling events per event"
  assert_source_call_keys "$calls" location getLocations DEHAM,DEHAM "$stack each event asks for Hamburg"
  assert_single_request "$(only_ops "$calls" getCargos,getLocations,getItineraries,listEventsFor)" "$stack the subscription's reads share one request id"
  assert_distinct_requests "$calls" "$stack the registrations are requests of their own"

  # 5. Cleanup: the subscriber is gone once the client has completed, and once a
  #    client has been killed mid-stream.
  wait_for_json "$base/debug/subscribers" '.graphql.ABC123' 0 5
  out="$SCRATCH/$stack-kill.out"
  : >"$out"
  compose_run --name "ch21-kill-$stack" client --url "$ws" --tracking-id ABC123 --count 5 --timeout 60 >"$out" 2>/dev/null &
  pid=$!
  wait_for_json "$base/debug/subscribers" '.graphql.ABC123' 1 60
  abc_ids+=("$(filler "$url" 19)")
  wait_for_lines "$out" 1 30
  docker kill "ch21-kill-$stack" >/dev/null
  wait "$pid" || true
  wait_for_json "$base/debug/subscribers" '.graphql.ABC123' 0 5

  # 5b. Order under load: three registrations sent at once arrive in the order the store issued their ids.
  out="$SCRATCH/$stack-order.out"
  : >"$out"
  compose_run client --url "$ws" --tracking-id ABC123 --count 3 --timeout 60 >"$out" 2>/dev/null &
  pid=$!
  wait_for_json "$base/debug/subscribers" '.graphql.ABC123' 1 60
  local -a burst=() bpids=()
  for hour in 14 15 16; do
    filler "$url" "$hour" >"$SCRATCH/$stack-burst-$hour" &
    bpids+=($!)
  done
  for p in "${bpids[@]}"; do wait "$p"; done
  mapfile -t burst < <(cat "$SCRATCH/$stack-burst-1"[456] | sort -t_ -k2 -n)
  abc_ids+=("${burst[@]}")
  rc=0
  wait "$pid" || rc=$?
  assert_eq "0" "$rc" "$stack the burst client exits 0"
  assert_json_eq "$(python3 -I -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "${burst[@]}")" "$(event_ids "$out")" "$stack a burst of three arrives in registration order"
  wait_for_json "$base/debug/subscribers" '.graphql.ABC123' 0 5

  # 6. The older graphql-ws subprotocol, once.
  out="$SCRATCH/$stack-legacy.out"
  err="$SCRATCH/$stack-legacy.err"
  : >"$out"
  compose_run client --url "$ws" --subprotocol graphql-ws --tracking-id ABC123 --count 1 --timeout 60 --frames >"$out" 2>"$err" &
  pid=$!
  wait_for_json "$base/debug/subscribers" '.graphql.ABC123' 1 60
  id1="$(filler "$url" 20)"
  abc_ids+=("$id1")
  rc=0
  wait "$pid" || rc=$?
  assert_eq "0" "$rc" "$stack graphql-ws client exits 0"
  assert_json_eq "[\"$id1\"]" "$(event_ids "$out")" "$stack graphql-ws delivers the event"
  assert_json_eq '[">>> connection_init","<<< connection_ack",">>> start","<<< data",">>> stop",">>> connection_terminate"]' \
    "$(frame_types "$err" '>>> connection_terminate')" "$stack the graphql-ws frames of the run"
  wait_for_json "$base/debug/subscribers" '.graphql.ABC123' 0 5

  # 7. GraphQL over SSE (graphql-sse, distinct connections mode): Python only.
  #    The Quarkus stack serves subscriptions over WebSocket.
  if [[ "$stack" == "python" ]]; then
    out="$SCRATCH/$stack-gqlsse.out"
    hdr="$(curl -sN -m 3 -D - -o /dev/null -X POST "$url" -H 'Content-Type: application/json' -H 'Accept: text/event-stream' --data "$SUB_BODY" || true)"
    assert_contains "text/event-stream" "$(tr -d '\r' <<<"$hdr" | grep -i '^content-type:')" "$stack graphql-sse content type"
    wait_for_json "$base/debug/subscribers" '.graphql.ABC123' 0 15
    sse_collect "$url" 30 1 -X POST -H 'Content-Type: application/json' -H 'Accept: text/event-stream' --data "$SUB_BODY" >"$out" &
    pid=$!
    wait_for_json "$base/debug/subscribers" '.graphql.ABC123' 1 30
    id1="$(filler "$url" 21)"
    abc_ids+=("$id1")
    wait "$pid"
    assert_eq "1" "$(wc -l <"$out" | tr -d ' ')" "$stack graphql-sse delivers one event"
    assert_eq "next" "$(json_field '.event' <<<"$(nth_line "$out" 1)")" "$stack graphql-sse event name"
    assert_json_eq "[\"$id1\"]" "$(gqlsse_ids "$out")" "$stack graphql-sse payload id"
    wait_for_json "$base/debug/subscribers" '.graphql.ABC123' 0 20
  fi

  # 8. The plain SSE feed. One live event, with the id: and event: lines of the
  #    protocol; then a reconnect with Last-Event-ID replays what came after it,
  #    in order, and continues live, with no id twice.
  local feed="$base/events/cargos/ABC123"
  hdr="$(curl -sN -m 3 -D - -o /dev/null -H 'Accept: text/event-stream' "$feed" || true)"
  assert_contains "text/event-stream" "$(tr -d '\r' <<<"$hdr" | grep -i '^content-type:')" "$stack feed content type"
  wait_for_json "$base/debug/subscribers" '.sse.ABC123' 0 15
  out="$SCRATCH/$stack-feed1.out"
  sse_collect "$feed" 30 1 -H 'Accept: text/event-stream' >"$out" &
  pid=$!
  wait_for_json "$base/debug/subscribers" '.sse.ABC123' 1 30
  id1="$(filler "$url" 22)"
  abc_ids+=("$id1")
  wait "$pid"
  assert_eq "handled" "$(json_field '.event' <<<"$(nth_line "$out" 1)")" "$stack feed event name"
  assert_eq "$id1" "$(json_field '.id' <<<"$(nth_line "$out" 1)")" "$stack feed event id is the new event id"
  data="$(json_field '.data' <<<"$(nth_line "$out" 1)")"
  assert_json_eq "{\"id\":\"$id1\",\"trackingId\":\"ABC123\",\"type\":\"CUSTOMS\",\"location\":\"DEHAM\",\"completionTime\":\"2026-10-09T22:00:00Z\"}" "$data" "$stack feed payload"
  wait_for_json "$base/debug/subscribers" '.sse.ABC123' 0 20

  # The reconnect: every ABC123 event after evt_10, in registration order, then one live.
  local -a expected_replay=("${abc_ids[@]:1}")
  out="$SCRATCH/$stack-feed2.out"
  sse_collect "$feed" 30 "$((${#expected_replay[@]} + 1))" -H 'Accept: text/event-stream' -H 'Last-Event-ID: evt_10' >"$out" &
  pid=$!
  wait_for_json "$base/debug/subscribers" '.sse.ABC123' 1 30
  id2="$(filler "$url" 23)"
  wait "$pid"
  expected_json="$(python3 -I -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "${expected_replay[@]}" "$id2")"
  assert_json_eq "$expected_json" "$(sse_ids "$out")" "$stack Last-Event-ID evt_10: the later events in order, then the live one, no id twice"
  wait_for_json "$base/debug/subscribers" '.sse.ABC123' 0 20

  echo "=== $stack: real-time check passed ==="
}

echo "=== Step 1: docker compose up ==="
compose_up "$COMPOSE_FILE" "$PROJECT"

echo
echo "=== Step 2: verify both stacks ==="
run_stack_check "quarkus" 8310
run_stack_check "python" 8311

# 10. The bounded queue (Python): a watcher that falls QUEUE_SIZE events behind is
#     ended. The script runs in the server image against the schema itself: it
#     subscribes, registers more events than the queue holds before the
#     subscriber reads again, and prints what the next result and the registry say.
echo
echo "=== Step 3: a lagging subscriber is ended (python) ==="
lagging="$(timeout 60 docker compose -p "$PROJECT" -f "$COMPOSE_FILE" exec -T python python - 2>/dev/null <<'PY'
import asyncio
from datetime import UTC, datetime

from app.deps import get_context
from app.handling import QUEUE_SIZE, HandlingStore, NewHandling
from app.model import HandlingEventType
from app.schema import schema
from app.sources import SourceCalls

DOCUMENT = "subscription($id: TrackingId!) { cargoHandled(trackingId: $id) { id } }"


async def main() -> None:
    store = HandlingStore()
    context = get_context(SourceCalls(0), store)
    results = await schema.subscribe(DOCUMENT, variable_values={"id": "ABC123"}, context_value=context)
    events = results.__aiter__()
    first = asyncio.ensure_future(anext(events))
    while store.subscriber_counts()["graphql"].get("ABC123") != 1:
        await asyncio.sleep(0.01)
    for _ in range(QUEUE_SIZE + 2):
        await store.append(
            NewHandling("ABC123", HandlingEventType.CUSTOMS, "DEHAM", None, datetime(2026, 10, 9, 1, 0, tzinfo=UTC)),
            None,
        )
    delivered = await first
    ended = await anext(events)
    print(delivered.data["cargoHandled"]["id"], ended.errors[0].message, store.subscriber_counts()["graphql"]["ABC123"])


asyncio.run(main())
PY
)"
assert_eq "evt_10 Internal server error. 0" "$lagging" "python a subscriber more than the queue size behind gets a masked error and leaves the registry"

echo
echo "PASS - Ch21 Real-time: Subscription.cargoHandled over graphql-transport-ws on Quarkus (SmallRye GraphQL)" \
     "and Python (Strawberry), in order and only for its cargo, with each event read afresh and every subscriber" \
     "cleaned up after a complete or a kill; the older graphql-ws once; GraphQL over SSE on Python; and a plain" \
     "SSE feed on both that resumes from Last-Event-ID without repeating an event."
