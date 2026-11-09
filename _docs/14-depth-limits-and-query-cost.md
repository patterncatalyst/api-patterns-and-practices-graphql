---
title: "Depth limits and query cost analysis"
order: 14
part: "Performance & Safety"
description: "Bounding what a client can ask for: depth, token and alias limits, and a list-aware cost budget enforced on graphql-java and on Strawberry before any source call."
duration: "12 min read"
---

## Learning objectives

By the end of this chapter you can:

- Price a nested selection bottom-up with the cost formula and explain why `cargos(first: 50)` multiplies everything beneath it.
- Distinguish a depth limit from a cost budget, and show why a 16-deep `first: 1` query is refused by depth alone while a shallow nested query needs the budget.
- Configure graphql-java's `MaxQueryComplexityInstrumentation` with a custom `FieldComplexityCalculator`, and Strawberry's `QueryCostLimiter` extension, to enforce the same budget on both stacks.
- Recognize the five amplification attacks (deep nesting, aliases, a huge page, a token flood, a batch array) and place each limit at the earliest pipeline stage that can refuse it before a source call.
- Price a fragment once per spread rather than once per definition, including under `@skip` and `@include`.

## Why this matters

A REST endpoint has a fixed shape: `GET /cargos/ABC123` does the work its author wrote, and the cost of the busiest route is a number you can measure. A GraphQL endpoint takes the shape from the request. Here is a nested query with every page at the ceiling the cursor-connection page cap allows:

```graphql
{ cargos(first: 50) { edges { node {
    handlingHistory(first: 50) { edges { node {
      cargo { handlingHistory(first: 50) { edges { node { id } } } } } } } } } } }
```

It is 157 bytes on one line, eleven fields deep and syntactically unremarkable. Read it as a multiplication: 50 cargos, each with up to 50 events, each event pointing back to its cargo, which lists up to 50 events again. That is up to 50 x 50 x 50 = 125,000 event nodes. The cost model below puts it at 385,151 units, and the server refuses it before it makes a single source call.

The page cap bounds each list. DataLoader batching bounds the calls a selection makes, one per level. Neither bounds the selection itself. Kleppmann and Riccomini's discussion of describing load in *Designing Data-Intensive Applications* gives the vocabulary: a service states the load it accepts and the response-time percentiles it promises, and a 99th-percentile promise cannot survive requests of unbounded cost. A cost limit states the load one request may carry.

## Five ways to ask for too much

{% include excalidraw.html file="14-amplification-attacks" alt="Five panels each show a request, the work it asks for, and what catches it. Deep nesting is 231 bytes and sixteen fields deep with a cost of 16, and the depth limit refuses it on both stacks. The alias attack is 16,093 bytes with 150 aliases of a seven-field lookup, and the alias limit refuses it on both stacks. A huge page, first: 5000, is 57 bytes and costs 15,001, and the cost budget refuses it on both stacks. A token flood is 66,003 bytes and 6,002 tokens, and the parser refuses it on both stacks. A batch array is 55 bytes with two operations, and Quarkus answers with a 200 and an error while Python answers with a 400." caption="Figure 14.1: Five requests that ask for too much. The text is small next to the work, except where the text itself is the attack." %}

- **Deep nesting.** Each level is one more field in the text. With a cycle in the schema (`Cargo` to `HandlingEvent` and back) depth is limited only by what the client types.
- **Aliases.** One field can be selected under many names, and each name runs. A 16 KB document of 150 aliases asks for 150 lookups.
- **A huge page.** `first: 5000` is 57 bytes.
- **A token flood.** The cost is in the lexer, the parser and the "Overlapping fields can be merged" validation rule, all before any resolver runs.
- **A batch array.** Some servers accept an array of operations in one body, which multiplies every other attack by the array length.

A limit that fires after a source call has protected nothing, so every refusal here must leave the source-call log empty.

## Where each limit fires

Each limit belongs at the earliest stage of request processing that has the information it needs, because an earlier refusal does less work.

{% include excalidraw.html file="14-limit-pipeline" alt="Two horizontal lanes show where each limit fires, one for SmallRye GraphQL on graphql-java and one for Strawberry on graphql-core, each with six stages: HTTP body, parse, validate, before execute, resolve and sources. In the SmallRye lane the HTTP layer refuses an array, the parser limits 5,000 tokens, validation has no limit of ours, and before execution a depth limit of 15, an alias limit of 20 and a cost budget of 1000 apply. In the Strawberry lane an array gets a 400, the parser limits 5,000 tokens, validation applies a depth limit of 14 and an alias limit of 20, and before execution a cost budget of 1000 applies. In both lanes the resolver enforces the page cap of 0 to 50. Dashed arrows from every limit lead down to a refused box that says HTTP 200, errors, no data and zero source calls, and only the arrow from resolve to sources reaches the source calls." caption="Figure 14.2: Where each limit fires. Every refusal ends before the sources are reached, and the two lanes refuse the same non-introspection documents." %}

| Stage | SmallRye on graphql-java | Strawberry on graphql-core |
|---|---|---|
| HTTP body | reads one JSON object | `batching_config` is unset, so an array is a 400 |
| Parse | `ParserOptions` for operations, 5,000 tokens | `MaxTokensLimiter`, 5,000 tokens |
| Validate | the standard rules (no limit of ours) | a depth rule (14) and an alias rule (20) |
| Before execute | depth instrumentation (15), alias instrumentation (20), cost instrumentation (1000) | `QueryCostLimiter` in `on_execute` (1000) |
| Resolve | the cursor-connection page cap | the same |

Everything before "Resolve" sees only the document and the variables, so those limits refuse a request without waiting for a resolver. The page cap needs the resolver's argument checks, but it still fires before the first source call.

## Depth is not cost

Depth and cost answer different questions, so keep both. A query sixteen fields deep with `first: 1` at every list costs 16 units, one per field, and a depth limit refuses it. The nested query above is eleven deep, under any depth limit anyone would choose, and costs 385,151 units. Only the cost limit refuses it.

Depth bounds the shape of the text, which also bounds recursion in the engine and nesting in the response. Cost bounds the work, which depends on page sizes. A schema with a cycle needs the first and any paginated schema needs the second.

The two engines count depth differently:

| Engine | Root field counts as | Introspection fields | Limit | Message |
|---|---|---|---|---|
| graphql-java | 1 | counted | 15 | `maximum query depth exceeded 16 > 15` |
| graphql-core rule | 0 | ignored | 14 | `'anonymous' exceeds maximum operation depth of 14` |

The introspection query GraphQL Inspector sends to read a schema is 15 levels deep, which sets the Quarkus limit. Both stacks refuse a 16-deep document and run its 15-deep prefix.

## A cost model for this schema

One rule, applied bottom-up:

```text
cost(field) = 0                            for __typename, __schema, __type
cost(field) = 1 + m x sum(cost(children))  otherwise
```

The multiplier `m` is what the field returns per parent:

| Field | `m` |
|---|---|
| `cargos`, `handlingHistory` | `first`, else `last`, else 10 (the default page) |
| `nodes` | the number of ids |
| anything else | 1 |

Unpaginated lists such as `Itinerary.legs` are not multiplied, because the domain bounds them, not the client. A negative page size counts as 0, so a field the resolver will refuse can never lower the price of its neighbor. A field, inline fragment or spread that `@skip` or `@include` excludes costs nothing, because the engine won't run it.

Figure 14.3 prices the nested query. The innermost `id` costs 1, its `node` 2 and its `edges` 3. The inner `handlingHistory(first: 50)` is 1 + 50 x 3 = 151, the `cargo` above it 152, then `node` and `edges` give 153 and 154. The outer `handlingHistory` is 1 + 50 x 154 = 7,701, and `cargos` is 1 + 50 x 7,703 = 385,151. Each page size multiplies everything beneath it, so moving one level up multiplies the total by about fifty. A four-cargo query with itinerary and delivery prices at 53 on both stacks.

{% include excalidraw.html file="14-cost-accumulation" alt="A chain of eleven boxes shows the cost of the nested query from the leaf to the root. The first row holds cargos with first 50 and cost 385,151, then edges 7,703, node 7,702, and handlingHistory with first 50 and cost 7,701. The second row runs right to left through edges 154, node 153, cargo 152, and handlingHistory with first 50 and cost 151. The third row holds edges 3, node 2 and id 1. Amber arrows labelled times 50 join each paginated field to its edges. A side panel computes the four-cargo query by hand: 1, 2, 2 each for the locations, 7 for legs, 8 for the itinerary, 2 for delivery, 12 for the node, 13 for the edges and 53 for the page. Below, four bars on a log scale show 53, 901, 7,651 and 385,151 against a budget line at 1,000." caption="Figure 14.3: The nested query priced bottom-up: 385,151 units. The four-cargo DataLoader batching query is 53." %}

## The budget and its boundary

The budget is 1,000 units. It is arbitrary the way a timeout is arbitrary, and it comes from the same place: measure the response time of real queries against their cost, find the cost at which the 99th percentile crosses the response time you promise, and set the budget a little under it. Use the percentile, not the mean, because the slowest requests are the ones users notice and they have the largest selections. The unit has no meaning outside the service; it is a ratio, only as good as the weights in the model.

The edge is sharp. Fix `cargos(first: 50)` and vary the inner page: `handlingHistory(first: n)` costs 151 + 150 n. At n = 5 the cost is 901 and the query runs. At n = 6 it is 1,051 and the server answers `maximum query complexity exceeded 1051 > 1000`.

{% include excalidraw.html file="14-cost-budget-boundary" alt="Six vertical bars show the cost of the same query with the inner page size from 1 to 6: 301, 451, 601, 751, 901 and 1,051. A horizontal line marks the budget of 1,000. The first five bars are below the line and are marked runs. The sixth bar is above the line, is highlighted, and is marked refused." caption="Figure 14.4: One page size decides admission: first: 5 costs 901 and runs, first: 6 costs 1,051 and is refused." %}

The message states both numbers so a client that sees `1051 > 1000` can halve its page and retry. The page that runs still carries the seed's booking outage on `GHI345`: the budget admitted the query, and the failure is the source's.

## Cost on SmallRye: graphql-java's calculator

SmallRye's own setting, `quarkus.smallrye-graphql.instrumentation-query-complexity`, installs `MaxQueryComplexityInstrumentation` with the default calculator, which charges every field 1 and so measures document size. Work depends on page sizes, so leave that setting unset and supply a `FieldComplexityCalculator`. It receives each field with its resolved arguments and the summed cost of its children, which is the shape of the formula.

SmallRye fires the `GraphQL.Builder` as a CDI event before `build()` when `quarkus.smallrye-graphql.events.enabled=true`. The builder exposes its instrumentation chain only through a build, and `instrumentation(...)` replaces the whole chain, so the observer reads the current chain from a throwaway build and appends to it. The depth limit fires first, then the alias limit, then the cost check. The same observer sets the token limit through the operation default of `ParserOptions`, the one that bounds a request.

```java
void addCostLimit(@Observes GraphQL.Builder builder) {
    // The token limit is set through graphql-java's ParserOptions: the
    // operation default is the one that bounds a request.
    ParserOptions.setDefaultOperationParserOptions(
            ParserOptions.getDefaultOperationParserOptions().transform(options -> options.maxTokens(maxTokens)));
    Instrumentation smallrye = builder.build().getInstrumentation();
    builder.instrumentation(new ChainedInstrumentation(List.of(
            smallrye,
            new MaxAliasesInstrumentation(maxAliases),
            new MaxQueryComplexityInstrumentation(maxCost, new TrackingCostCalculator(maxTokens)))));
}
```

The calculator is the formula, one method:

{% include codetabs.html langs="Quarkus|Python" %}

```java
@Override
public int calculate(FieldComplexityEnvironment environment, int childComplexity) {
    String name = environment.getField().getName();
    if (name.startsWith("__")) {
        return 0;
    }
    Map<String, Object> arguments = environment.getArguments();
    long multiplier =
            switch (name) {
                case "cargos", "handlingHistory" -> pageSize(arguments);
                case "nodes" -> arguments.get("ids") instanceof List<?> ids ? ids.size() : 1;
                default -> 1;
            };
    return (int) Math.min(maxFieldCost, 1 + multiplier * childComplexity);
}
```

```python
def field(self, parent: GraphQLNamedType, node: FieldNode) -> int:
    name = node.name.value
    if name.startswith("__"):
        return 0
    definition: GraphQLField | None = (
        parent.fields.get(name) if isinstance(parent, GraphQLObjectType | GraphQLInterfaceType) else None
    )
    if definition is None:
        return 1
    children = 0
    if node.selection_set is not None:
        children = self.selection_set(get_named_type(definition.type), node.selection_set)
    return min(self.field_cap, 1 + self.multiplier(name, definition, node) * children)
```

A variable arrives in the calculator as a `BigDecimal` and a literal as an `Integer`, so read the page size as a `Number`.

The `min` clamps each field's cost so sums stay in 32-bit range, because graphql-java adds sibling costs in an `int`. Clamping to the budget would give the right verdict but report 1,001 for every large query. Clamp to `Integer.MAX_VALUE / 5000 = 429,496` instead, where 5,000 is the token limit: a request holds at most 5,000 fields, so any sum of siblings stays under 2,147,483,647, and the clamp moves no total below 429,496. Python clamps the same way, so both stacks report 858,992 for two clamped siblings. The calculator is the one piece of cost code you write yourself: a price list that charges a list field for its page size. graphql-java supplies the traversal, the variable handling and the limit.

## Cost on Strawberry: an extension that runs before execution

A validation rule sees the document, not the variables, so `first: $n` can't be priced there. The `on_execute` hook runs after parsing, validation and variable coercion and before the first resolver. `QueryCostLimiter` selects the operation, coerces its variables with graphql-core's `get_variable_values`, walks the selection with the walker whose `field` method is the Python tab above, and raises before it yields:

```python
walker = _Walker(schema, fragments, variables, self.field_cap)
cost = walker.selection_set(root, operation.selection_set)
if cost > self.max_cost:
    raise GraphQLError(f"maximum query complexity exceeded {cost} > {self.max_cost}")
```

The message is graphql-java's text, so a client can't tell the stacks apart. An error raised there gives `data: null` and no source call. It has no original exception, so the `MaskErrors` predicate leaves its message alone, and it carries no `extensions.code`, like every request-level refusal here. With variables, `first: $n` at `n = 50` costs 7,651 and is refused, and at `n = 2` costs 1 + 2 x (3 + 3 x 2) = 19 and runs.

Strawberry builds one extension per request and deprecates passing an instance, so every extension is a factory:

```python
extensions=[
    partial(MaskErrors, should_mask_error=should_mask, error_message="Internal server error."),
    partial(MaxTokensLimiter, max_token_count=MAX_TOKENS),
    partial(depth_limiter, max_depth=14),
    partial(alias_limiter, max_alias_count=20),
    partial(QueryCostLimiter, max_cost=settings.max_query_cost, max_tokens=MAX_TOKENS),
],
```

## Aliases, fragments and tokens

**Aliases.** The alias limit is separate from the budget: the budget prices what a selection fetches, and an alias repeats a selection at no extra charge. On Strawberry it is a graphql-core validation rule installed through `AddValidationRules`, with the counting rules and text of `MaxAliasesLimiter`. On graphql-java it is a `MaxAliasesInstrumentation` in the same chain, firing before the cost check with the same rule and message. Both count every aliased field, descend into inline fragments, count a fragment spread again wherever it appears, and ignore `@skip`. A 150-alias document is refused with `150 aliases found. Allowed: 20` on both stacks.

**Fragments.** Neither engine prices a fragment definition twice. graphql-java's analyzer visits a fragment definition the first time it is spread and skips later spreads in the operation, and the Python walker repeats that rule so both stacks quote one number. A spread that `@skip` removes is not a visit, so a live spread of the same fragment is still priced. The execution engine merges fields with equal response keys, so a fragment of two selections priced at 2 also runs once.

Because a fragment is priced where it is first spread, the price depends on where that is:

| Document | Price |
|---|---|
| Eight aliases of `cargo { ...F }`, `F` selecting `handlingHistory(first: 50)` | 159 (152 + 7), and `pageEvents` runs eight times |
| The same fragment under two `cargos(first: 50)` selections | 7,752 |
| The same fragment spread at the root and under `cargos(first: 50)` | 253 |

Fragment pricing is a weakness of arbitrary text. In production the server should run only documents it has seen before, which is what persisted queries deliver.

**Tokens.** A document is split into tokens, parsed, then validated, and the overlapping-fields rule is the expensive part of validation. Neither the cost nor the depth limit helps against a document the parser hasn't finished reading, so the token limit sits at the parser. A 6,002-token flood is refused on both stacks with different text: Strawberry says `Syntax Error: Document contains more than 5000 tokens. Parsing aborted.`, and SmallRye answers `Unparseable input document`, the text it gives for any syntax error, with no token count. Both refuse before validation.

## Batches of operations

Each operation in a JSON array passes through the same limits, so an array of ten 1,000-unit queries is 10,000 units under a budget of 1,000. Strawberry's `batching_config` is unset by default, so an array answers `400 Batching is not enabled`; when you set it, `max_operations` bounds the array. SmallRye reads one JSON object, and an array gets a 200 with `Unparseable request` and no data. Neither makes a source call. If you enable batching, bound the sum, not the single query.

## Caps that remain

The page cap of 0 to 50 still fires in the resolver. `cargos(first: 51)` costs only 154 units, well under the budget, and the resolver refuses it with `BAD_USER_INPUT` and `first must be between 0 and 50` before any source call. The cap protects one list and the budget protects the whole selection.

`nodes` is the field whose list is as long as the caller made it. The budget closes that: 1,000 copies of `loc_NLRTM` cost 1,001 units and are refused, while one id runs and returns one object.

| Decide | Rule |
|---|---|
| How much shape a client may ask for | Set depth, token and alias limits from each framework, plus one cost budget with the same formula on both stacks |
| What to charge | Price a list by its page size; a rate limit on requests can't do this |
| What production traffic may run | Only known documents, which persisted queries allow; the limits are the backstop for arbitrary text |

> **Decision**
>
> Limits turn the operational and security cost axis into a number: a service that lets the client choose the shape states how much shape it accepts, and a cost budget does that where a request rate limit cannot. A field's multiplier is the number of owner calls it fans out to, and DataLoader batching decides how many calls those become. No field, argument or nullability changes; the limits are configuration plus one price list. Set depth and token limits from each framework, an alias limit on both, one cost budget with the same formula on both stacks, and run only known documents in production.

> **🤖 Explore with your agent**
>
> "In examples/14-query-cost, set the budget to 500 (TRACKING_QUERY_MAX_COST on Quarkus, TRACKING_MAX_QUERY_COST on Python) and price `cargos(first: 4)` with itinerary and delivery, `handlingHistory(first: 5)` under `cargos(first: 50)` and `nodes` with 600 ids by the rule cost(field) = 1 + m x sum(cost(children)). Say which three run or are refused at 500, and what each stack's message says."
>
> Check: send the three documents to ports 8240 and 8241; each refusal must read `maximum query complexity exceeded N > 500` with N equal to your hand-priced total (the first prices at 53, the second at 901, the third at 601).

## Build, run, observe

```bash
docker compose -f examples/14-query-cost/compose.yaml up -d --build
curl -s localhost:8240/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ cargos(first: 50) { edges { node { handlingHistory(first: 50) { edges { node { cargo { handlingHistory(first: 50) { edges { node { id } } } } } } } } } } }"}'
docker compose -f examples/14-query-cost/compose.yaml down -v
```

Quarkus answers on port 8240 and Python on 8241. The body is `{"errors":[{"message":"maximum query complexity exceeded 385151 > 1000", ...}]}`, and port 8241 answers the same message with `"data": null`. Run `bash examples/14-query-cost/verify.sh` for the whole sequence on both stacks; it prints `PASS` only when every case holds on both and every refusal made 0 source calls. The budget is `TRACKING_QUERY_MAX_COST` on Quarkus and `TRACKING_MAX_QUERY_COST` on Python.

| Request | Quarkus | Python |
|---|---|---|
| four-cargo query | `VWX901`, `XYZ789`, `STU678`, `DEF456`; 8 calls | the same data; 6 calls |
| the nested query above | `maximum query complexity exceeded 385151 > 1000` | the same |
| `cargos(50) { handlingHistory(50) }` | `... exceeded 7651 > 1000` | the same |
| 16 deep, `first: 1` | `maximum query depth exceeded 16 > 15` | `'anonymous' exceeds maximum operation depth of 14` |
| 15 deep | runs | runs |
| `handlingHistory(first: 5)` | admitted at 901; 6 edges | the same |
| `handlingHistory(first: 6)` | `... exceeded 1051 > 1000` | the same |
| 150 aliases | `150 aliases found. Allowed: 20` | the same |
| 802 aliases, two aliased chains | `802 aliases found. Allowed: 20` | the same |
| two aliased `first: 5000` chains | `... exceeded 858992 > 1000` | the same |
| a fragment of `cargo` and `trackingId` | priced 2; runs; one `getCargo` | the same |
| one fragment under 8 aliases | priced 159; runs; 8 `pageEvents` | the same |
| a skipped spread, then a live one | `... exceeded 7652 > 1000` | the same |
| a skipped `cargos(first: 50)` beside `__typename` | runs | the same |
| `first: 5000` | `... exceeded 15001 > 1000` | the same |
| `first: 51` | `BAD_USER_INPUT`, `first must be between 0 and 50` | the same |
| `first: -1000` beside a full page | `... exceeded 7652 > 1000` | the same |
| `nodes` with 1,000 ids | `... exceeded 1001 > 1000` | the same |
| 6,002 tokens | `Unparseable input document` | `... more than 5000 tokens ...` |
| a JSON array body | 200, `application/graphql-response+json`, no data, `Unparseable request` | 400, `text/plain`, `Batching is not enabled` |
| `first: $n`, `n = 50` / `n = 2` | `... exceeded 7651 > 1000` / runs | the same |
| `__schema` | free | free |

Experiments:

- Send `handlingHistory(first: 6)` under `cargos(first: 50)`: it costs 1,051 and is refused. Change the inner page to 5 and it runs at 901.
- Send `cargos(first: 51)`: the cost is 154, so the resolver's page cap refuses it, not the budget.
- Send a JSON array body to both ports: Quarkus answers 200 with `Unparseable request`, Python answers 400.

## For deeper coverage

- Martin Kleppmann & Chris Riccomini, *Designing Data-Intensive Applications*, 2nd edition (O'Reilly): load, response-time percentiles and tail latency, the vocabulary behind the budget.
- Artur Czemiel, *GraphQL Best Practices* (Packt, 2024): schema design, query limits and security, the source of the amplification attacks. Both books are on the [Bibliography](../../bibliography/) page.
- Cloud Native Design Patterns, chapter "Security": the broader operational-and-security-cost axis these limits are one instance of.
- [graphql-java documentation: Instrumentation](https://www.graphql-java.com/documentation/instrumentation/): `MaxQueryComplexityInstrumentation` and `MaxQueryDepthInstrumentation`.
- [Quarkus SmallRye GraphQL guide](https://quarkus.io/guides/smallrye-graphql): the configuration reference.
- Strawberry: [QueryDepthLimiter](https://strawberry.rocks/docs/extensions/query-depth-limiter) and [MaxAliasesLimiter](https://strawberry.rocks/docs/extensions/max-aliases-limiter), whose rules the Python limits follow, [MaxTokensLimiter](https://strawberry.rocks/docs/extensions/max-tokens-limiter) and [custom extensions](https://strawberry.rocks/docs/guides/custom-extensions).
- [OWASP GraphQL Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/GraphQL_Cheat_Sheet.html): the denial-of-service defenses implemented here.
- The GraphQL specification's "Validation" and "Executing Requests" sections define the stages the limits sit between.
