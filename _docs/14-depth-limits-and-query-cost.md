---
title: "Depth limits and query cost analysis"
order: 14
part: "Performance & Safety"
description: "Bounding what a client can ask for: depth, token and alias limits, a list-aware cost model computed by hand and on both stacks, the budget and its boundary, graphql-java's complexity instrumentation against a Strawberry execution extension, the per-field clamp, skipped selections, fragment pricing, batch refusal, and the caps that remain."
duration: "17 min read"
---

## Learning objectives

By the end of this chapter you can:

- Price a nested selection bottom-up with the chapter's cost formula and explain why `cargos(first: 50)` multiplies everything beneath it.
- Distinguish a depth limit from a cost budget, and show why a 16-deep `first: 1` query is refused by depth alone while the chapter's deeply nested query needs the cost budget.
- Configure graphql-java's `MaxQueryComplexityInstrumentation` with a custom `FieldComplexityCalculator`, and Strawberry's `QueryCostLimiter` extension, to enforce the same budget on both stacks.
- Recognize the five amplification attacks (deep nesting, aliases, a huge page, a token flood, a batch array) and place each limit at the earliest pipeline stage that can refuse it before a source call.
- Price a fragment once per spread rather than once per definition, including under `@skip` and `@include`.

## Why this matters

The opening REST-to-GraphQL comparison predicted a query of a few hundred bytes that fans out across thousands of backend calls. This chapter builds the defenses. The query is one the reader has already seen, and the server in `examples/14-query-cost/` refuses it, with the same number on both stacks, before it makes a single source call.

The code starts from the DataLoader batching example, so the seed, the keyset cursors and the error contract are unchanged, the DataLoader batching code is untouched, and the schema is the one `verify.sh` diffs against the canonical SDL. What it adds sits in front of execution: a depth limit, a token limit, an alias limit, and one list-aware cost budget that both stacks compute with the same formula and report in the same words.

## The client chooses the bill

A REST endpoint has a fixed shape. `GET /cargos/ABC123` does the work its author wrote, and the cost of the busiest route is a number you can measure. A GraphQL endpoint takes the shape from the request. Here is the nested query from the opening comparison, with every page at the ceiling the Relay cursor-connection page cap allows:

```graphql
{ cargos(first: 50) { edges { node {
    handlingHistory(first: 50) { edges { node {
      cargo { handlingHistory(first: 50) { edges { node { id } } } } } } } } } } }
```

On one line it is 157 bytes, and a few hundred when indented as above. It is eleven fields deep and syntactically unremarkable. Read it as a multiplication: 50 cargos, each with up to 50 events, each event pointing back to its cargo, which lists up to 50 events again. That is up to 50 x 50 x 50 = 125,000 event nodes, and the seed in this example is tiny. The cost model below puts the same query at 385,151 units.

The Relay cursor-connection page cap bounds each list. DataLoader batching bounds the number of calls a selection makes, so the calls here would be one per level. Neither bounds the selection itself, and that is what this chapter bounds. The discussion of describing load in Martin Kleppmann and Chris Riccomini's *Designing Data-Intensive Applications*, 2nd edition, gives the vocabulary: a service states the load it accepts and the response-time percentiles it promises, and a promise about the 99th percentile cannot survive requests whose cost is unbounded. A limit on query cost is how a GraphQL service states the load a single request may carry.

## Five ways to ask for too much

Figure 14.1 lists the five requests that `verify.sh` sends, each with the size of its text and the work it asks for.

{% include excalidraw.html file="14-amplification-attacks" alt="Five panels each show a request, the work it asks for, and what catches it. Deep nesting is 231 bytes and sixteen fields deep with a cost of 16, and the depth limit refuses it on both stacks. The alias attack is 16,093 bytes with 150 aliases of a seven-field lookup, and the alias limit refuses it on both stacks. A huge page, first: 5000, is 57 bytes and costs 15,001, and the cost budget refuses it on both stacks. A token flood is 66,003 bytes and 6,002 tokens, and the parser refuses it on both stacks. A batch array is 55 bytes with two operations, and Quarkus answers with a 200 and an error while Python answers with a 400." caption="Figure 14.1: Five requests that ask for too much. The text is small next to the work, except where the text itself is the attack." %}

- **Deep nesting.** Each level is one more field in the text, and with a cycle in the schema (`Cargo` to `HandlingEvent` and back) the depth is limited only by what the client types.
- **Aliases.** One field can be selected under many names, and each name runs. A 16 KB document of 150 aliases asks for 150 lookups.
- **A huge page.** `first: 5000` is 57 bytes.
- **A token flood.** The cost is in the lexer, the parser and the validation rule that checks overlapping fields ("Overlapping fields can be merged", in the specification's "Validation" section), all before any resolver runs.
- **A batch array.** Some servers accept an array of operations in one body, which multiplies every other attack by the array length.

Each rejected case in `verify.sh` is followed by a read of the source-call log, and the log is empty every time. A limit that fires after a source call has already protected nothing.

## Where each limit fires

A request passes through the stages of the specification's "Executing Requests" section, with the HTTP layer in front. Each limit belongs at the earliest stage that has the information it needs, because an earlier refusal does less work. Figure 14.2 places them.

{% include excalidraw.html file="14-limit-pipeline" alt="Two horizontal lanes show where each limit fires, one for SmallRye GraphQL on graphql-java and one for Strawberry on graphql-core, each with six stages: HTTP body, parse, validate, before execute, resolve and sources. In the SmallRye lane the HTTP layer refuses an array, the parser limits 5,000 tokens, validation has no limit of ours, and before execution a depth limit of 15, an alias limit of 20 and a cost budget of 1000 apply. In the Strawberry lane an array gets a 400, the parser limits 5,000 tokens, validation applies a depth limit of 14 and an alias limit of 20, and before execution a cost budget of 1000 applies. In both lanes the resolver enforces the page cap of 0 to 50. Dashed arrows from every limit lead down to a refused box that says HTTP 200, errors, no data and zero source calls, and only the arrow from resolve to sources reaches the source calls." caption="Figure 14.2: Where each limit fires. Every refusal ends before the sources are reached, and the two lanes refuse the same non-introspection documents." %}

The two lanes differ because the frameworks hook in at different places.

| Stage | SmallRye on graphql-java | Strawberry on graphql-core |
|---|---|---|
| HTTP body | reads one JSON object | `batching_config` is unset, so an array is a 400 |
| Parse | `ParserOptions` for operations, 5,000 tokens | `MaxTokensLimiter`, 5,000 tokens |
| Validate | the standard rules (no limit of ours) | a depth rule (14) and an alias rule (20), both validation rules |
| Before execute | depth instrumentation (15), then an alias instrumentation (20), then the cost instrumentation (1000) | `QueryCostLimiter` in `on_execute` (1000) |
| Resolve | the Relay cursor-connection page cap | the same |

Everything left of "Resolve" sees only the document and the variables, which is why those limits can refuse a request without having to wait for a resolver. The page cap is the exception: it needs the resolver's own argument checks, and it still fires before the first source call, because the check runs before the resolver reads anything.

## Depth is not cost

Depth and cost answer different questions, so the example keeps both. Take a query that goes sixteen fields deep with `first: 1` at every list: it costs 16 units, one per field. A depth limit refuses it. Take the nested query above: it is eleven deep, under every depth limit anyone would choose, and it costs 385,151 units. Only the cost limit refuses it.

Depth bounds the shape of the text, which also bounds recursion in the engine and the number of nested objects in the response. Cost bounds the work, which depends on page sizes. A schema with a cycle needs the first and any paginated schema needs the second. Depth enters the cost only through nesting: each level adds its own unit, and each paged level multiplies everything beneath it.

The depth numbers need care, because the two engines count differently. graphql-java counts a root field as depth 1, and it counts introspection fields: the query that GraphQL Inspector sends to read a schema is 15 levels deep, so the Quarkus limit is 15, and the deep query in `verify.sh` is 16 fields deep so that it exceeds it. The Python depth rule ignores `__*` fields and counts a root field as 0, so its limit is 14. Both refuse the 16-deep document, and both run its 15-deep prefix, so the lanes refuse the same non-introspection documents. The messages differ, and `verify.sh` asserts each: `maximum query depth exceeded 16 > 15` on Quarkus, and `'anonymous' exceeds maximum operation depth of 14` on Python.

## A cost model for this schema

The model has one rule, applied bottom-up:

```text
cost(field) = 0                            for __typename, __schema, __type
cost(field) = 1 + m x sum(cost(children))  otherwise
```

The multiplier `m` is what the field returns per parent. On `cargos` and `handlingHistory` it is `first`, else `last`, else 10, the default page of the Relay cursor-connection pattern. On `nodes` it is the number of ids, which is the bound the Global Object Identification pattern left to this chapter. On everything else it is 1. That includes unpaginated lists such as `Itinerary.legs`, which the domain bounds, not the client, and the model says so by not multiplying them. A negative page size counts as 0, so a field the resolver will refuse can never lower the price of its neighbour. A field, inline fragment or spread that `@skip` or `@include` excludes costs nothing, because the engine will not run it.

Figure 14.3 prices the nested query above. The innermost `id` costs 1, its `node` 2 and its `edges` 3. The inner `handlingHistory(first: 50)` is 1 + 50 x 3 = 151, the `cargo` above it is 152, and the next `node` and `edges` give 153 and 154. The outer `handlingHistory` is 1 + 50 x 154 = 7,701, and `cargos` is 1 + 50 x 7,703 = 385,151. Each page size multiplies everything beneath it, which is why moving one level up multiplies the total by about fifty. The side panel works the DataLoader batching chapter's four-cargo query by hand and gets 53, which is what both stacks compute for it.

{% include excalidraw.html file="14-cost-accumulation" alt="A chain of eleven boxes shows the cost of the nested query from the leaf to the root. The first row holds cargos with first 50 and cost 385,151, then edges 7,703, node 7,702, and handlingHistory with first 50 and cost 7,701. The second row runs right to left through edges 154, node 153, cargo 152, and handlingHistory with first 50 and cost 151. The third row holds edges 3, node 2 and id 1. Amber arrows labelled times 50 join each paginated field to its edges. A side panel computes the four-cargo query by hand: 1, 2, 2 each for the locations, 7 for legs, 8 for the itinerary, 2 for delivery, 12 for the node, 13 for the edges and 53 for the page. Below, four bars on a log scale show 53, 901, 7,651 and 385,151 against a budget line at 1,000." caption="Figure 14.3: The nested query priced bottom-up: 385,151 units. The four-cargo DataLoader batching example is 53." %}

## The budget and its boundary

The budget in the example is 1,000 units. The choice is arbitrary in the way a timeout is arbitrary, and it comes from the same place. Measure the response time of real queries against their cost, take the cost at which the 99th percentile crosses the response time you promise, and set the budget a little under it. The percentile matters more than the mean for the reason Kleppmann and Riccomini give: the slowest requests are the ones users notice, and they are the ones with the largest selections. The unit has no meaning outside the service. It is a ratio, and the ratio is only as good as the weights in the model.

Figure 14.4 shows how sharp the edge is. Fix `cargos(first: 50)` and vary the inner page: `handlingHistory(first: n)` costs 151 + 150 n. At n = 5 the cost is 901 and the query runs; at n = 6 it is 1,051 and the server refuses it with `maximum query complexity exceeded 1051 > 1000`.

{% include excalidraw.html file="14-cost-budget-boundary" alt="Six vertical bars show the cost of the same query with the inner page size from 1 to 6: 301, 451, 601, 751, 901 and 1,051. A horizontal line marks the budget of 1,000. The first five bars are below the line and are marked runs. The sixth bar is above the line, is highlighted, and is marked refused." caption="Figure 14.4: One page size decides admission: first: 5 costs 901 and runs, first: 6 costs 1,051 and is refused." %}

A client that hits the edge needs to be able to react, so the message states both numbers. A client that sees `1051 > 1000` can halve its page and retry. The page that runs still returns the whole seed, and the response carries the seed's booking outage on `GHI345`: the budget admitted the query, and the failure is the source's.

## Cost on SmallRye: graphql-java's calculator

SmallRye has a cost setting, `quarkus.smallrye-graphql.instrumentation-query-complexity`, and the example leaves it unset. It installs graphql-java's `MaxQueryComplexityInstrumentation` with the default calculator, which gives every field a cost of 1 and so measures the size of the document. The work a document asks for depends on its page sizes, so the example supplies its own calculator.

The same class accepts a `FieldComplexityCalculator`, which receives each field with its resolved arguments and the summed cost of its children. That is exactly the shape of the formula, so the example supplies one. The instrumentation joins SmallRye's own chain, which holds the depth limit and its parsed-query cache. SmallRye fires the `GraphQL.Builder` as a CDI event before `build()` when `quarkus.smallrye-graphql.events.enabled=true`, which the example already enables for its schema details. The builder exposes its chain only through a build, and calling `instrumentation(...)` sets the whole chain, so the observer reads the current chain from a throwaway build and appends to it:

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

The depth limit fires first, then the alias limit, then the cost check. The first statement sets the token limit through graphql-java's `ParserOptions`, on the operation default, which is the one that bounds a request.

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

A variable arrives in the calculator as a `BigDecimal` and a literal as an `Integer`, so the page-size helper reads a `Number`.

The `min` clamps each field's cost so that sums stay within 32-bit range: graphql-java adds sibling costs in an `int`. Clamping to the budget would be enough for the verdict but would report 1,001 for every large query, so the example clamps to `Integer.MAX_VALUE / 5000 = 429,496`, where 5,000 is the token limit. A request holds at most 5,000 fields, so the sum of any siblings stays under the 32-bit limit of 2,147,483,647, and the clamp moves no total below 429,496. Python clamps the same way, and the two stacks report 858,992 for two clamped siblings. This is the one piece of cost code the example writes itself: a price list that charges a list field for its page size, and the class says so in a comment. graphql-java supplies the traversal, the variable handling and the limit, and the example supplies a price list.

## Cost on Strawberry: an extension that runs before execution

Strawberry ships a token limiter, and the example adds the cost limit as an extension. A validation rule sees the document, not the variables, so `first: $n` could not be priced there. The `on_execute` hook sees both: it runs after parsing, validation and variable coercion and before the first resolver, with the parsed document in hand. `QueryCostLimiter` selects the operation, coerces its variables with graphql-core's `get_variable_values`, walks the selection with the walker whose `field` method is the Python tab above, and raises before it yields:

```python
walker = _Walker(schema, fragments, variables, self.field_cap)
cost = walker.selection_set(root, operation.selection_set)
if cost > self.max_cost:
    raise GraphQLError(f"maximum query complexity exceeded {cost} > {self.max_cost}")
```

The message is graphql-java's text, character for character, so a client cannot tell the stacks apart. An error raised there gives `data: null` and no source call. It has no original exception, so the `MaskErrors` predicate leaves its message alone, and it carries no `extensions.code`, like every request-level refusal in the chapter. `verify.sh` asserts the same message on both stacks for each of the nested query above (385,151), the 7,651 variant, the boundary case (1,051), the 15,001-unit huge page and the 1,001-unit `nodes` call. It also asserts a variable case: `first: $n` with `n = 50` costs 7,651 and with `n = 2` costs 1 + 2 x (3 + 3 x 2) = 19 and runs.

Every extension is a factory. The schema lists `partial(QueryCostLimiter, max_cost=settings.max_query_cost, max_tokens=MAX_TOKENS)` beside the token limiter and the two limit rules, because Strawberry 0.335 builds one extension per request and deprecates passing an instance:

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

**Aliases.** The Python alias rule rejects 150 aliases with `150 aliases found. Allowed: 20`; it is a graphql-core validation rule, installed through Strawberry's `AddValidationRules`, with the counting rules and the text of Strawberry's `MaxAliasesLimiter`. The alias limit is separate from the cost budget: the budget prices what a selection fetches, and an alias repeats a selection at no extra charge. On graphql-java the example adds the limit to the same builder chain, a `MaxAliasesInstrumentation` that fires before the cost check and uses the same rule and message. It counts every aliased field, descends into inline fragments, and counts a fragment spread again wherever it appears. `@skip` exempts nothing. The 150-alias document is refused with `150 aliases found. Allowed: 20` on both stacks.

**Fragments.** The cost model counts each fragment definition once. The fragment case in `verify.sh` is priced 2, one for `cargo` and one for `trackingId`, and runs once: the execution engine collects fields by response key and merges equal ones, and `verify.sh` confirms one `getCargo` call. graphql-java's analyser visits each fragment definition the first time it is spread and skips every later spread in the operation, and the Python walker repeats that rule so that both stacks quote one number. A spread that `@skip` removes is not a visit: graphql-java aborts it before it records the fragment, so a live spread of the same fragment is still priced. `verify.sh` sends a skipped spread followed by a live spread under `cargos(first: 50)` and asserts `7652 > 1000` on both stacks, and it sends a skipped `cargos(first: 50)` beside `__typename`, which runs on both.

A fragment definition is priced where it is first spread, and the example asserts the consequence. Eight aliases of `cargo { ...F }`, with `F` selecting `handlingHistory(first: 50)`, are priced 152 + 7 = 159, and `pageEvents` runs eight times. The same fragment under two `cargos(first: 50)` selections is priced 7,752. The same fragment spread at the root and again under `cargos(first: 50)` is priced 253. In production the server runs only documents it has seen before, which is what persisted queries deliver, and this chapter's limits bound arbitrary text.

**Tokens.** A document is first split into tokens, then parsed, then validated, and the overlapping-fields rule is the expensive part of validation. Neither the cost nor the depth limit helps against a document the parser has not finished reading. `T_FLOOD` is 6,002 tokens of `__typename` and is refused by the token limit of 5,000 on both stacks, with different text: Strawberry says `Syntax Error: Document contains more than 5000 tokens. Parsing aborted.`, and SmallRye answers `Unparseable input document`, the same text it gives for a syntax error and with no token count. The refusal comes before validation on both.

## Batches of operations

Some servers accept a JSON array of operations in one request. Each operation passes through the same limits, so an array of ten 1,000-unit queries is 10,000 units under a budget of 1,000. Strawberry's `batching_config` is unset by default, so an array answers `400 Batching is not enabled`; when set, its `max_operations` bounds the array. SmallRye reads one JSON object, and an array gets a 200 response with `Unparseable request` and no data. Both make no source call. If you enable batching, bound the sum, not the single query.

## Caps that remain

The Relay cursor-connection page cap of 0 to 50 still holds and still fires in the resolver. `cargos(first: 51)` costs only 154 units, well under the budget, and the resolver refuses it with `BAD_USER_INPUT` and `first must be between 0 and 50`, before any source call. The cost limit and the page cap are independent: the cap protects one list, the budget protects the whole selection.

`nodes` is the field whose list is as long as the caller made it, and the Global Object Identification pattern left its length to this chapter. The cost budget closes that: 1,000 copies of `loc_NLRTM` cost 1,001 units and are refused, while one id runs and returns one object.

## On the wire

Start the stack and send the nested query:

```bash
docker compose -f examples/14-query-cost/compose.yaml up -d --build
curl -s localhost:8240/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ cargos(first: 50) { edges { node { handlingHistory(first: 50) { edges { node { cargo { handlingHistory(first: 50) { edges { node { id } } } } } } } } } } }"}'
docker compose -f examples/14-query-cost/compose.yaml down -v
```

The body is `{"errors":[{"message":"maximum query complexity exceeded 385151 > 1000", ...}]}`. Port `8241` answers the same message with `"data": null`. Each row below is asserted by `verify.sh`, and each refusal also makes 0 source calls. The two priced rows are asserted by adding a `nodes` field of known cost, so the refusal message carries the sum.

| Check | Quarkus | Python |
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
| the fragment case | priced 2 (1002 with 999 ids added); runs; one `getCargo` | the same |
| one fragment under 8 aliases | priced 159 (1002 with 842 ids added); runs; 8 `pageEvents` | the same |
| a skipped spread, then a live one | `... exceeded 7652 > 1000` | the same |
| a skipped `cargos(first: 50)` beside `__typename` | runs | the same |
| `first: 5000` | `... exceeded 15001 > 1000` | the same |
| `first: 51` | `BAD_USER_INPUT`, `first must be between 0 and 50`, `data` null | the same |
| `first: -1000` beside a full page | `... exceeded 7652 > 1000` | the same |
| `nodes` with 1,000 ids | `... exceeded 1001 > 1000` | the same |
| 6,002 tokens | `Unparseable input document` | `... more than 5000 tokens ...` |
| a JSON array body | 200, `application/graphql-response+json`, no data, `Unparseable request` | 400, `text/plain`, `Batching is not enabled` |
| `first: $n`, `n = 50` / `n = 2` | `... exceeded 7651 > 1000` / runs | the same |
| `__schema` and conformance | free; conforms; only `Subscription` unserved | the same |

`bash examples/14-query-cost/verify.sh` runs the whole sequence on both stacks and prints `PASS` only when both hold.

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>Limits are where the <em>operational and security cost</em> axis of the GraphQL decision framework becomes a number. A GraphQL service that lets the client choose the shape has to state how much shape it accepts, and a budget on estimated cost does that where a rate limit on requests cannot. The <em>aggregation across sources</em> axis supplies the weights, because the multiplier of a field is the number of owner calls it fans out to, and DataLoader batching decides how many calls those become. The <em>contract and evolution style</em> axis is untouched: no field, argument or nullability changed, and the limits are configuration plus one price list. The tracking view therefore sets depth and token limits from each framework, adds an alias limit on both (a validation rule on Strawberry, and a small instrumentation on graphql-java), adds one cost budget with the same formula on both stacks, writes its own price list, and runs only the known documents that persisted queries allow for production traffic.</p></div>

## Review

- The chapter's cost formula prices a nested selection bottom-up, with each paginated field multiplying the cost of its children by its page size.
- A 16-deep `first: 1` query is refused by the depth limit alone, while the chapter's nested query needs the cost budget, because depth and cost bound different things.
- `MaxQueryComplexityInstrumentation` with a custom `FieldComplexityCalculator` on graphql-java, and the `QueryCostLimiter` extension on Strawberry, enforce the same 1,000-unit budget on both stacks.
- Five amplification attacks (deep nesting, aliases, a huge page, a token flood, a batch array) are each refused at the earliest pipeline stage that can reject them before a source call.
- A fragment is priced once per spread, not once per definition, and a spread removed by `@skip` or `@include` costs nothing.

## Where this goes next

This chapter bounded the request: depth and token limits, an alias limit, a list-aware cost model that both stacks compute identically, a budget with a measured boundary, a refusal for batch arrays, and zero source calls for every refused request. The limits are a backstop for a server that accepts arbitrary text, and the production control is to run only documents the server already knows.

Persisted queries build that control: Apollo's automatic persisted-queries protocol, a trusted-document mode that refuses unknown text, and persisted queries over `GET`, which HTTP and CDN caching can then use.

For the limits themselves, read the graphql-java documentation on [instrumentation](https://www.graphql-java.com/documentation/instrumentation/) (`MaxQueryComplexityInstrumentation` and `MaxQueryDepthInstrumentation`), the Quarkus [SmallRye GraphQL guide](https://quarkus.io/guides/smallrye-graphql) for the configuration reference, and the Strawberry guides to [QueryDepthLimiter](https://strawberry.rocks/docs/extensions/query-depth-limiter) and [MaxAliasesLimiter](https://strawberry.rocks/docs/extensions/max-aliases-limiter), whose rules the Python limits follow, [MaxTokensLimiter](https://strawberry.rocks/docs/extensions/max-tokens-limiter) and [custom extensions](https://strawberry.rocks/docs/guides/custom-extensions). The [OWASP GraphQL Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/GraphQL_Cheat_Sheet.html) lists the denial-of-service defenses this chapter implements. The GraphQL specification's "Validation" and "Executing Requests" sections define the stages the limits sit between. Martin Kleppmann and Chris Riccomini's *Designing Data-Intensive Applications*, 2nd edition, covers load, response-time percentiles and tail latency. Artur Czemiel's *GraphQL Best Practices* treats query limits among its security topics. Both books are on the [Bibliography](../../bibliography/) page.

## For deeper coverage

- Martin Kleppmann & Chris Riccomini, *Designing Data-Intensive Applications*, 2nd edition (O'Reilly): load, response-time percentiles and the vocabulary behind this chapter's budget.
- Artur Czemiel, *GraphQL Best Practices* (Packt, 2024): schema design, query limits and security, the book this chapter's amplification attacks draw on.
- Cloud Native Design Patterns, chapter "Security": the broader operational-and-security-cost axis this chapter's limits are one instance of.
- [graphql-java documentation: Instrumentation](https://www.graphql-java.com/documentation/instrumentation/): `MaxQueryComplexityInstrumentation` and `MaxQueryDepthInstrumentation`, the classes this chapter configures.
- [OWASP GraphQL Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/GraphQL_Cheat_Sheet.html): the denial-of-service defenses this chapter implements.
