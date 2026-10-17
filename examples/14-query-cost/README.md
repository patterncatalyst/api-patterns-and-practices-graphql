# Ch14 - Depth limits and query cost analysis

A client chooses the shape of a query, so the server bounds the shape before it runs. This example
puts four limits in front of execution on both stacks: depth, tokens, aliases and a
list-aware cost budget of 1000 that prices `first`, `last` and `len(ids)`. Both stacks compute the
same cost for the same document and report it in the same words. Every refused request makes zero
source calls; `verify.sh` reads the source-call log to prove it.

## The served slice

`contracts/schema/shipping/*.graphql` is the canonical SDL. This chapter serves everything in it
except `Subscription`, which Chapter 21 builds. The schema, the seed, the batching, the cursors and the
error contract are Chapter 13's. The limits change which documents are accepted, not which fields exist,
and `assert_sdl_conforms` runs under them. This example does not repeat the limits of later chapters,
and later chapters do not carry this chapter's; production would run all of them together.

## The cost model

```
cost(field) = 0                              for __* fields
cost(field) = 1 + m * sum(cost(children))    otherwise
m = first, else last, else 10   on cargos and handlingHistory
m = len(ids)                    on nodes
m = 1                           everywhere else
```

A negative page size counts as 0, and a field, inline fragment or spread that `@skip` or `@include`
excludes costs nothing. The budget is 1000. A fragment definition is priced where it is first
spread (see "Design notes").

| Query | Cost | Result |
|---|---|---|
| Q_FAN: `cargos(first: 4)` with itinerary and delivery | 53 | runs |
| Q_CH1: `cargos(50) { handlingHistory(50) { cargo { handlingHistory(50) } } }` | 385151 | refused |
| Q_WIDE_COST: `cargos(50) { handlingHistory(50) }` | 7651 | refused |
| Q_EDGE(n): `handlingHistory(first: n)` under `cargos(first: 50)` | 151 + 150 n | n = 5 (901) runs; n = 6 (1051) refused |

## Run it

```bash
bash examples/14-query-cost/verify.sh
```

`verify.sh` brings both services up with `docker compose`, runs the cases below in a fixed order,
diffs each live schema against `contracts/schema/` and tears the stack down. It prints `PASS` only if
every check holds on **both** stacks. It needs Docker Engine with the `docker compose` plugin and
Node/npm (for the pinned `graphql-inspector` in `contracts/`).

To explore by hand:

```bash
docker compose -f examples/14-query-cost/compose.yaml up -d --build
curl -s localhost:8240/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ cargos(first: 50) { edges { node { handlingHistory(first: 50) { edges { node { cargo { handlingHistory(first: 50) { edges { node { id } } } } } } } } } } }"}'
docker compose -f examples/14-query-cost/compose.yaml down -v
```

Use port `8241` for the Python stack. For a non-container run:
`cd quarkus && mvn quarkus:dev -Dquarkus.http.port=8240`, or
`cd python && uv sync && uv run uvicorn app.main:app --port 8241`. Set
`TRACKING_SOURCE_LATENCY_MS=250 TRACKING_DEBUG_ENDPOINTS=true` for the behaviour compose gives. The
budget is `TRACKING_QUERY_MAX_COST` on Quarkus and `TRACKING_MAX_QUERY_COST` on Python (default 1000
on both).

## The source-call log (lab only)

`GET /debug/source-calls` answers `200 {"calls":[...]}`, ordered by `startMs`; `DELETE` clears the
log and answers `204`. The endpoints answer only when `TRACKING_DEBUG_ENDPOINTS=true` (compose sets it)
and sit beside `/graphql`. A refused request leaves the log empty.

## Ports

| Stack | Container | Host | Endpoint |
|---|---|---|---|
| Quarkus | 8080 | 8240 | `/graphql` (health at `/q/health`) |
| Python | 8080 | 8241 | `/graphql` (health at `/health`) |

Compose project `gql-ch14-query-cost`, containers `ch14-query-cost-*`. Telemetry is off by default.
Add the observability file (`docker compose -f compose.yaml -f compose.observability.yaml up
--build`) to send it to LGTM, which publishes the fixed host ports 3000, 4317, 4318, 9090, 3100 and
3200, so run one example's observability stack at a time.

## On the wire

Each value below is asserted by `verify.sh`. Every refusal is also asserted to make 0 source calls.
Rejections are request-level errors: HTTP 200, no `data` (Quarkus omits the key, Python sends
`null`), and no `extensions.code`.

| Case | Request | Quarkus | Python |
|---|---|---|---|
| Q_FAN | `cargos(first: 4)` as Chapter 13 | the four cargos; 8 calls | the same four; 6 calls |
| Q_CH1 | Chapter 1's nested query, 157 bytes on one line | `maximum query complexity exceeded 385151 > 1000` | the same message |
| Q_WIDE_COST | `cargos(50) { handlingHistory(50) }` | `... exceeded 7651 > 1000` | the same |
| D_DEEP | 16 fields deep, `first: 1` throughout, cost 16 | `maximum query depth exceeded 16 > 15` | `'anonymous' exceeds maximum operation depth of 14` |
| 15 deep | the same, one level shorter | runs | runs |
| Q_EDGE(5) | `handlingHistory(first: 5)` under `cargos(first: 50)` | admitted (cost 901): 6 edges, with the seed's booking outage on `GHI345` | admitted: 6 edges, the same outage |
| Q_EDGE(6) | `first: 6` | `... exceeded 1051 > 1000` | the same |
| A_BOMB | 150 aliases of one lookup, 16,093 bytes | `150 aliases found. Allowed: 20` | the same |
| A_FRAG | an 11-alias fragment spread twice, plus one alias | `23 aliases found. Allowed: 20` | the same |
| A_CHAINS | two chains of `first: 50` pages with 400 aliases at each leaf, 802 aliases | `802 aliases found. Allowed: 20` | the same |
| C_CLAMP | two aliased chains of `first: 5000` pages | `... exceeded 858992 > 1000` (2 x 429496) | the same |
| F_FAN | the fragment case | priced 2 (1002 with 999 ids added), runs, one `getCargo` | the same |
| F_REUSE | one fragment under 8 aliases | priced 159 (152 + 7; 1002 with 842 ids added), runs, 8 `pageEvents` | the same |
| F_SKIP | `...F @skip(if: true)` under one alias, then `...F` under `cargos(first: 50)` | `... exceeded 7652 > 1000` | the same |
| S_FIELD | `cargos(first: 50) @skip(if: true)` beside `__typename` | runs, 0 source calls | the same |
| F_REUSE, two pages | the fragment under two `cargos(first: 50)` | `... exceeded 7752 > 1000` | the same |
| `first: 5000` | `cargos(first: 5000) { edges { node { trackingId } } }` | `... exceeded 15001 > 1000` | the same |
| `first: 51` | the same with 51 (cost 154) | `BAD_USER_INPUT`, `first must be between 0 and 50`, `data` null | the same |
| `first: -1000` beside a page | a negative size counts as 0 | `... exceeded 7652 > 1000` | the same |
| N_IDS | `nodes(ids: [1000 x "loc_NLRTM"])`, 12,024 bytes | `... exceeded 1001 > 1000` | the same |
| one id | `nodes(ids: ["loc_NLRTM"])` | `[{"id":"loc_NLRTM"}]` | the same |
| T_FLOOD | 6,002 tokens, 66,003 bytes | `Unparseable input document` | `Syntax Error: Document contains more than 5000 tokens. Parsing aborted.` |
| B_ARRAY | `[{"query":...},{"query":...}]` | 200, no `data`, `Unparseable request` | 400, `Batching is not enabled` |
| variables | `cargos(first: $n) { ... handlingHistory(first: $n) }` | `n = 50`: `... exceeded 7651 > 1000`; `n = 2`: runs (cost 19) | the same |
| introspection | the whole schema through `__schema` | costs 0, runs | the same |
| schema | live schema | conforms to `contracts/schema/`; `finalArrivalDate` deprecated; only `Subscription` unserved | the same |

## Design notes

Pinned versions: Quarkus 3.40.1 with SmallRye GraphQL 2.18.5 on graphql-java 25.0; Strawberry 0.335.0
on graphql-core 3.3.0.

**The `GraphQL.Builder` observer.** With `quarkus.smallrye-graphql.events.enabled=true`, SmallRye
fires `GraphQL.Builder` as a CDI event before `build()`. `QueryCost` reads SmallRye's chain from a
throwaway `builder.build().getInstrumentation()` and sets `ChainedInstrumentation(List.of(smallrye,
cost))`, so depth rejections fire before the alias and cost checks.

**Depth counts differ by engine.** graphql-java counts a root field as depth 1 and counts
introspection fields. GraphQL Inspector's introspection query is 15 levels deep, so the Quarkus limit
is 15 and `D_DEEP` is 16 levels deep. The Python depth rule (`app/limits.py`, the rules of Strawberry's
`QueryDepthLimiter`) skips `__*` fields and counts a root field as depth 0, so the equal limit on
Python is 14. The 15-deep prefix of `D_DEEP` runs on both and `D_DEEP` itself is refused on both.

**The token limit.** `QueryCost` sets the operation default through graphql-java's
`ParserOptions.setDefaultOperationParserOptions` from `tracking.query.max-tokens` (5000). SmallRye
reports the refusal as `Unparseable input document`, with no locations and no token count.

**`instrumentation-query-complexity`.** SmallRye's own setting gives every field a cost of 1. It
stays unset here because the example supplies a list-aware calculator.

**The alias limit.** The Python alias rule (`app/limits.py`, installed through `AddValidationRules`,
with the counting rules of Strawberry's `MaxAliasesLimiter`) counts every aliased field in the
document: through fields and inline fragments, through fragment spreads, and ignoring `@skip`.
`QueryCost.MaxAliasesInstrumentation` applies the same rule on Quarkus in `beginExecuteOperation`,
installed through the same `@Observes GraphQL.Builder` chain, after SmallRye's depth limit and before
the cost check. It raises `AbortExecutionException` with Strawberry's text,
`<n> aliases found. Allowed: 20` (`tracking.query.max-aliases`). `A_BOMB` is refused by it on both
stacks.

**The per-field clamp.** `TrackingCostCalculator` clamps each field's cost to
`Integer.MAX_VALUE / maxTokens`, where `maxTokens` is the token limit (5000): 2147483647 / 5000 =
429496. A request has at most 5000 tokens, so at most 5000 fields, and the sum of any siblings is at
most 5000 x 429496 = 2147480000, within the 32-bit range. The clamp is above the budget by a factor of
429, so it changes no verdict, and the largest total any other assertion quotes (385151) is below it.
The Python walker clamps each field to the same 429496 (`QueryCostLimiter(max_tokens=...)`), so a
document that reaches the clamp reports one total on both stacks: `C_CLAMP`, two aliased
`first: 5000` chains, is `... exceeded 858992 > 1000` (2 x 429496).

**`@skip` and `@include`.** graphql-java's analyser checks the directives before it visits a node, and
a skipped spread is not recorded as a visit of its fragment. The Python walker evaluates both
directives, with graphql-core's `get_directive_values`, on every field, inline fragment and spread, and
records a fragment only when a live spread is walked. `F_SKIP` is refused on both stacks
(`7652 > 1000`), and `{ cargos(first: 50) @skip(if: true) { ... } __typename }` runs on both.

**Fragment pricing.** graphql-java's traverser prices each fragment definition the first time it is
spread, in document order: `cargo { ...F0 ...F1 }` with `F1 { ...F0 }` costs the same as
`cargo { ...F0 }`, and `a: cargo { ...F } b: cargo { ...F }` costs 153. The fragment case `F_FAN` is priced 2 and runs one field. `F_REUSE` prices a 152-unit selection
once for eight aliases (159 units). The Python walker repeats the rule so that both stacks quote one
number. For page reuse, `cargo { ...F } cargos(first: 50) { edges { node { ...F } } }` is priced 253
(`F_REUSE_PAGE`). Chapter 15's trusted documents are the production control
for arbitrary text.

**Variables.** SmallRye hands the calculator a variable's value as a `BigDecimal` and a literal as an
`Integer`, so the calculator reads a `Number`. Strawberry's extension runs after variable coercion
for the request and prices with `graphql.execution.values.get_argument_values`, which sees the
variables.

**Exceptions in `on_execute`.** A `GraphQLError` raised before `yield` gives `data: null` and no source
call. It has no `original_error`, so `MaskErrors` keeps its message and no code is added.

**Batch arrays.** SmallRye reads one JSON object. An array answers 200 with `Unparseable request` and no
data, content type `application/graphql-response+json`. Strawberry answers `400 Batching is not
enabled` as `text/plain`. `verify.sh` asserts both content types.

**The cost code is the example's price list.**
`TrackingCostCalculator` (about 25 lines on graphql-java's traversal) and `QueryCostLimiter` (about 80
lines on graphql-core) price each list by its page size, each with a comment saying so. Tokens use each framework's own limiter and depth uses SmallRye's on Quarkus; on Python the depth and alias limits are validation rules in `app/limits.py` with Strawberry's rules and messages, and on Quarkus the alias limit is a small instrumentation.

## Diagram

`architecture.svg` / `architecture.excalidraw` (regenerate with
`python3 -I diagrams/examples/14-query-cost-architecture.py`) show the compose topology: a client sending
queries to each stack, the limits in front of each, both stacks diffed against the canonical SDL, and
the opt-in `compose.observability.yaml` override.
