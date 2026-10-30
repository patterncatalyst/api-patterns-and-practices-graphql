---
title: "Error handling"
order: 9
part: "Reliability: Errors & Partial Results"
description: "How GraphQL reports failure: request errors against execution errors, the anatomy of an error, partial data, a stable extensions.code vocabulary, masking unexpected failures on both stacks, status codes and media types, and the choice between errors[], payload userErrors and result unions."
duration: "16 min read"
---

## Learning objectives

By the end of this chapter you can:

- Distinguish a request error (no resolver ran) from an execution error (partial `data` plus a `path` to the failure).
- Read an error's `message`, `locations`, `path`, and `extensions` and know which parts a client may rely on.
- Mask an unexpected exception as `Internal server error.` behind an allowlist, while routing an outage like `SERVICE_UNAVAILABLE` to the client via `extensions.code`.
- Explain why the null in `data` can land at a different point than the error's `path`, depending on nullability.
- Weigh top-level `errors`, payload `userErrors`, and a result union as three ways to report failure, and justify which one a given failure belongs in.

## Why this matters

Nullability propagation followed a null upward through non-null fields, and the mutation chapter returned refused input as `userErrors` data. Both stopped short of the error itself: what it contains, which parts a client can rely on, and which parts the server must keep to itself. This chapter gives failures a contract. The tracking view fails in three ways, one outage and two unexpected failures, and both stacks answer them with the same shape.

The code is in `examples/09-error-handling/`. It starts from the mutation example, adds no schema, and restores three fault seeds: `JKL567` sails on a voyage whose service is down, `MNO901` loads at a location code the location service does not know, and `PQR234` makes the handling service fail with an unexpected exception that carries an internal shard name. What is new is the error behaviour. An outage is an exposed error with a code, anything unexpected is masked as `Internal server error.`, and the detail goes to the server log. `verify.sh` asserts every claim below on both stacks.

## Two kinds of failure, one array

The GraphQL specification separates failures by when they happen. A **request error** occurs before execution begins: the document does not parse, it fails validation, a variable does not coerce, or the operation cannot be selected. No resolver runs, so there is no `data` entry at all (Python sends `"data":null`). An **execution error** occurs while a resolver is running. Execution continues, so the response carries `data` with a null where the field failed, and the error carries a `path` to that field. Older editions of the specification call these field errors. The current term is execution error, and this book uses it.

Both kinds arrive in the same top-level `errors` array, which is why the array alone does not tell a client what happened. The shape does. Errors with no `data` mean the request was rejected and nothing was fetched. Errors beside `data` mean the server did what it could and part of the answer is missing. A third outcome has no `errors` at all: a mutation's `userErrors` are ordinary data in a successful response.

{% include excalidraw.html file="09-error-taxonomy" alt="Three horizontal lanes. The first lane, a request error, runs through parse, validate, coerce variables and select operation, and exits to a box saying errors with locations and no path, no data (Python sends data null), and no resolver ran. The second lane, an execution error, shows a resolver that either raises an exposed error or an unexpected one that is masked, and both exit to a box saying data plus errors with a path, where the null lands at the nearest nullable ancestor. The third lane, a domain failure, shows a mutation validating its input and exiting to a box saying data with userErrors and no errors key. The first exit box notes the GraphQL-over-HTTP draft asks for a 4xx and both stacks answer 200, and the other two note the response is 200 on both stacks." caption="Figure 9.1: Three kinds of failure and the response each produces. Only the first happens before a resolver runs." %}

The origin matters for what a client does next. A request error is a defect in the client: retrying the same document fails the same way, and the fix is in the code that built it. An execution error may be transient, as an outage often is, so a retry can succeed. A domain failure is neither: the input was understood and refused, and the user can correct it.

## Anatomy of an error

The specification's "Response" section defines the error format, under "Errors" and "Error Result Format". Each entry is a map with these keys:

- `message` is a string for a developer. Its wording belongs to the engine or the resolver, and clients must not parse it.
- `locations` is a list of line and column pairs that point into the request document. Request errors and most execution errors have it.
- `path` is the response path of the field that failed. It exists only for execution errors, because a request error has no field. Each step is a response key (the alias when the selection has one) or a list index, and an index is a JSON number: `0`, not `"0"`.
- `extensions` is a map the server may fill with anything. It is the only place for custom keys, and the specification advises against adding other keys to the error map, since a future edition may claim them.

A request error is the engine speaking, and its entries come from the validation rules of the specification's "Validation" section or from coercion. An unknown field gives `Cannot query field 'weight' on type 'Cargo'.` on Strawberry and `Validation error (FieldUndefined@[cargo/weight]) : Field 'weight' in type 'Cargo' is undefined` on Quarkus. Same failure, same shape, two sentences. That is why the example asserts structure and codes and not request-error wording.

The order of the entries in `errors` carries no meaning, so a client looks up an error by its `path` and does not read it by position. The harness does the same: every assertion in `verify.sh` finds an error by its path when a response carries more than one.

Two details deserve a check on a live server. Aliases show in paths, so `bug: cargo(...)` that fails at `delivery` reports `["bug","delivery"]`. And `locations` is optional in the specification. Strawberry and SmallRye both send it for resolver failures, while graphql-java's own null-in-a-non-null-field error arrives with a `path` and no `locations`. A client treats the key as optional.

## Partial data: errors beside data

The strongest argument for the execution-error model is a query that is half right. Three aliases ask for three cargos:

```graphql
{
  ok: cargo(trackingId: "ABC123") { trackingId }
  outage: cargo(trackingId: "JKL567") { itinerary { legs { voyage { number } } } }
  bug: cargo(trackingId: "PQR234") { delivery { transportStatus } }
}
```

The response has all three keys, in selection order. `ok` is intact. `outage` is a cargo whose itinerary has one leg and whose `voyage` is null, because the voyage service is down for `V404X`. `bug` is null, because the handling service failed under `delivery`. Two errors explain the two holes.

{% include excalidraw.html file="09-partial-data-errors" alt="Two panels. The left panel shows the data tree with three branches. The ok branch is a solid box with the tracking id resolved. The outage branch shows a solid box for cargo JKL567 and a dashed box for itinerary legs zero voyage, null. The bug branch is a dashed box, null at the cargo. The right panel shows two error boxes. The outage error has the code SERVICE_UNAVAILABLE, the message voyage service unavailable and the path outage, itinerary, legs, zero, voyage. The bug error has the code null on Quarkus and no extensions on Python, the message Internal server error. and the path bug, delivery. An amber arrow runs from each path to its hole." caption="Figure 9.2: The response to the three-alias query. A path names where it broke, and the null lands at the nearest nullable ancestor." %}

A client with one request per screen section can render what arrived and mark the missing parts. A client that treated any entry in `errors` as a failed request would throw away two usable answers here. That is the payoff of nullability propagation's fuses: each alias sits under its own nullable root field, so one failure cannot take another alias with it.

## Where the null lands

The error's `path` and the null in `data` are not always at the same place. The path names the field that failed. The null goes where the type system allows it. `Leg.voyage` is nullable, so the failure and the hole coincide: `["cargo","itinerary","legs",0,"voyage"]`. `Cargo.delivery` is non-null, so a null cannot be placed there, and the engine nulls the nearest nullable ancestor instead, which is `cargo`. The error still says `["bug","delivery"]`, and a client that looks for a null at that path finds the parent null instead.

`MNO901` combines both rules. The location source answers null for `XXBAD`, `Leg.loadLocation` is non-null, `legs` is a non-null list of non-null legs, and `Itinerary.legs` itself is non-null. The null climbs from `loadLocation` through the leg, the list and the itinerary object to `Cargo.itinerary`, the first nullable position on the way up. One error, one hole, `itinerary` null, and `trackingId` still `MNO901`. The error count is one however far the null travels: it is recorded where the failure happened, and the propagation adds nothing.

## A code vocabulary in extensions

A message is for a person, and a client that switches on it breaks whenever someone rewords it. A client that needs to act on a failure, say by retrying, needs something stable. That is `extensions.code`, a short string from a vocabulary the service owns and documents.

| `extensions.code` | Raised for | Message | Exposed |
|---|---|---|---|
| `SERVICE_UNAVAILABLE` | a source outage (`V404X`) | `voyage service unavailable` | yes |
| none | anything unexpected | `Internal server error.` | masked |

The codes are contract and the messages are not, so the codes follow the same evolution rules as enum values: adding one is safe for a client that has a default branch and breaks one that does not. The breaking-change gate returns to that. Pagination adds `BAD_USER_INPUT` to the vocabulary for cursors that pass coercion and are still invalid.

A client that reads an error can follow a short order. First, is `data` absent? Then the request was rejected, nothing was fetched, and the fix is in the client. Otherwise, walk the `errors` entries, find the hole by `path`, and decide per entry: a `SERVICE_UNAVAILABLE` is worth a bounded retry or a degraded rendering, a masked error with no code is worth showing a generic apology while the server log keeps the exception, its stack and the time, and an unknown code falls to the same generic branch. That last rule is what makes it safe for the service to add a code later.

Request errors have no code. SmallRye and graphql-core generate them before any resolver runs, in their own words, and the example does not rewrite them. A client branches on their structure: errors present and no `data`.

## Masking what clients must not see

An unexpected exception carries whatever its author put in the message: a table name, a shard, a host, a stack. In `PQR234` it is `handling projection corrupted on shard handling-primary-3`. Showing that to a client exposes the topology and invites probing, and it does not help the client, which cannot fix a corrupted shard. The rule has two halves: the client gets a generic message, and the operator gets everything in the server log.

Both frameworks implement this as an allowlist. Nothing is shown unless the service listed it, so a new exception class added next year is masked by default.

{% include codetabs.html langs="Quarkus|Python" %}

```java
@ErrorCode("SERVICE_UNAVAILABLE")
public class SourceUnavailableException extends RuntimeException {

    public SourceUnavailableException(String message) {
        super(message);
    }
}
```

```python
class ExposedError(Exception):
    """A failure whose message is safe to show a client."""

    code: ClassVar[str]

    def __init__(self, message: str) -> None:
        super().__init__(message)
        self.extensions = {"code": self.code}


class SourceUnavailable(ExposedError):
    code = "SERVICE_UNAVAILABLE"
```

SmallRye hides the message of every unchecked exception by default. `show-runtime-exception-message` lists the classes whose messages are shown, which makes it the allowlist, and `default-error-message` sets the replacement. The `@ErrorCode` annotation sets `extensions.code`. The section below supplies the code for every other exception.

```properties
quarkus.smallrye-graphql.show-runtime-exception-message=com.patterncatalyst.shipping.tracking.SourceUnavailableException
quarkus.smallrye-graphql.default-error-message=Internal server error.
quarkus.smallrye-graphql.error-extension-fields=code
quarkus.smallrye-graphql.print-data-fetcher-exception=true
```

The same file lists `ExceptionNameErrorExtensionProvider`, so the `exception` field is gone too; `DeclaredErrorCodeProvider` is the only provider left.

Strawberry ships a schema extension, `MaskErrors`, that replaces the message of the errors a predicate selects. The predicate here inverts the usual reading: it masks every error whose original exception is not an `ExposedError`, so the allowlist is the class hierarchy.

```python
def should_mask(error: GraphQLError) -> bool:
    return error.original_error is not None and not isinstance(error.original_error, ExposedError)


schema = strawberry.Schema(
    query=Query,
    mutation=Mutation,
    config=StrawberryConfig(scalar_map=SCALAR_MAP),
    extensions=[MaskErrors(should_mask_error=should_mask, error_message="Internal server error.")],
)
```

An error with no original exception came from the engine itself, a request error, and keeps its message. `MaskErrors` rebuilds a masked error without its `extensions`, so a masked error carries no code either. The predicate also decides what a resolver may raise: a `GraphQLError` raised directly is masked, because it is not an `ExposedError`, so a resolver raises a subclass of `ExposedError` for anything a client should read.

{% include excalidraw.html file="09-error-masking" alt="A left to right flow. A source throws an exception, the resolver does not catch it, and the engine builds an error holding the path, the message and the original exception. The error passes an amber allowlist box that names the SmallRye show-runtime-exception-message setting and the Strawberry should_mask predicate. An arrow labelled on the list leads to an exposed box where the client gets the message and the code SERVICE_UNAVAILABLE. An arrow labelled anything else leads to a masked box where the client gets Internal server error, with no detail and no class name. A dashed arrow from the engine error, labelled always, leads down to a server log box that keeps the full message, the stack, the time and the shard name." caption="Figure 9.3: Masking is an allowlist. The client sees only what the service listed; the log always sees everything." %}

The log half needs the same attention as the response half. Strawberry logs the original exception, with its traceback, through the `strawberry.execution` logger before `MaskErrors` builds the replacement. SmallRye logs the exception when `print-data-fetcher-exception` is on. `verify.sh` reads each service's log after the masked request and requires `handling-primary-3` in it, and it requires the same string, the exception class names and the package name to be absent from the response.

The code is the one field the service decides for itself, and the example supplies it only for exceptions that declare one. `DeclaredErrorCodeProvider` expresses that rule. It is registered through SmallRye's `ErrorExtensionProvider` SPI, found by ServiceLoader, and supplies `extensions.code` only for exceptions annotated `@ErrorCode`. The built-in provider file is removed with Quarkus `quarkus.class-loading.removed-resources`, so an unexpected failure carries `"code": null`:

```java
public class DeclaredErrorCodeProvider implements ErrorExtensionProvider {
    @Override
    public String getKey() {
        return "code";
    }

    @Override
    public JsonValue mapValueFrom(Throwable exception) {
        ErrorCode code = exception.getClass().getAnnotation(ErrorCode.class);
        return code == null ? null : Json.createValue(code.value());
    }
}
```

```properties
quarkus.class-loading.removed-resources."io.smallrye\:smallrye-graphql"=META-INF/services/io.smallrye.graphql.api.ErrorExtensionProvider
```

The class is listed in `META-INF/services/io.smallrye.graphql.api.ErrorExtensionProvider`. Quarkus now sends `"code": null` for a masked error, where Python sends no `extensions`, and a client reads both as no code. `verify.sh` asserts both values, which keeps the registration checked across upgrades, since the removal names a file inside the SmallRye jar.

The null in a non-null field splits the stacks the same way. On Python the `TypeError` behind a null `loadLocation` is an unexpected exception, so the client reads `Internal server error.`. On Quarkus the error is graphql-java's own and is not a fetch exception, so it is shown: the message names the field and the path, and the extension is `classification`. Both stacks null the same `itinerary`.

## Status codes and media types

The execution model measured the request-error half of this against the GraphQL-over-HTTP working draft, which has one "Status Codes" section: a result with no `data` entry gets a `4xx` or `5xx` (`400` for a parse failure, `422` for validation and coercion), and legacy `application/json` clients are handled the same way, with `Content-Type: application/json` on a `2xx`. Both stacks answer `200` for a request error under either `Accept` header; the draft recommends a `4xx` or `5xx` for this case. Quarkus labels the response with the media type asked for; Strawberry always answers `application/json`, the media type the draft assigns to a legacy client. This chapter adds the execution error. When `data` is present beside `errors`, the draft says the status must be `2xx` and recommends `294` and only alongside `application/graphql-response+json`, a custom "Partial Success" code outside the IANA registry that clients unaware of it treat as `200`. The draft's own example elsewhere shows `200` for an execution error, and both stacks send plain `200`.

The example sends both `Accept` headers for a request error and an execution error, and every case answers `200`. The media type differs: Quarkus echoes `application/graphql-response+json` when asked for it, and Strawberry answers `application/json` whatever the header says. A client must include `application/graphql-response+json` in `Accept`, and `application/graphql-response+json, application/json;q=0.9` is the safe form when unsure.

The consequence for operations is the one the REST-to-GraphQL comparison flagged. A request error and an execution error both answer `200` on both stacks, so a latency-and-status dashboard sees neither, and no stack here sends `294` to separate the partial answer from a clean one. A monitor has to count entries in `errors`, ideally split by `extensions.code` and by operation, and that count is what later becomes a metric.

## Errors as data

The mutation chapter returned a domain failure as `userErrors`: an unknown voyage comes back as `[{"code":"UNKNOWN_VOYAGE","field":["input","voyageNumber"]}]` with no `errors` key, a null `handlingEvent`, and no write. A third envelope exists. A mutation can return a union of its outcomes, and the failure is a type:

```graphql
union RegisterHandlingEventResult = RegisterHandlingEventSuccess | ValidationFailed

type ValidationFailed {
  code: UserErrorCode!
  field: [String!]!
  message: String!
}
```

This is a sketch and the example does not serve it. The canonical contract keeps the payload shape, and a second write surface would only confuse it.

{% include excalidraw.html file="09-failure-shapes" alt="Three columns show one failure, an unknown voyage, in three envelopes. The first column, top-level errors, shows an errors entry with a message and extensions code and a null data, because the payload is non-null and the failure nulls the whole data field, a note that the client branches on errors being present and then on the code, and a note that monitors count it as a failure. The second column, payload userErrors, which the example serves, shows data with a null handlingEvent and a userErrors entry with code UNKNOWN_VOYAGE and a field path, a note that the client branches on userErrors being non-empty, and a note that no errors key appears. The third column, a result union, shows a ValidationFailed member selected by typename, a note that the client branches on typename with an inline fragment per member, and a note that adding a member is a dangerous change." caption="Figure 9.4: One failure in three envelopes. The book serves the middle shape and sketches the union." %}

The trade-offs are concrete. A union is exhaustive: a client that selects `... on` for every member sees a compile-time error from its code generator when the server adds one, which is useful. It is also the cost, because adding a member is a dangerous change, which the breaking-change gate measures, and a client with no default branch breaks. A union also makes every outcome a `__typename` branch, where a payload keeps the common path flat: `handlingEvent` is there on success, `userErrors` is an empty list, and a client that ignores the list still renders. The payload shape also keeps a single place for a list of failures. A union member holds one failure unless the type wraps a list.

The book keeps payload `userErrors` for expected, user-correctable failures, the top-level `errors` for everything a user cannot fix, and a code vocabulary for the second kind. The choice follows the decision framework's axes, not taste. On the *contract and evolution style* axis, a payload that can grow is cheaper to evolve than a union that cannot gain a member safely. On the *operational and security cost* axis, keeping user mistakes out of `errors` keeps the failure count meaningful.

## What a message should say

A message is read by a developer with a request in front of them and sometimes, carelessly, by an end user. It should say what happened to this request in terms of the domain: `voyage service unavailable`, `No voyage has number V999X.`. It should not carry internals: no host names, class names, SQL, shard names or stack. It should not instruct the client to parse it, and it should not change meaning between releases, because someone will match on it anyway. Everything a machine needs is in `code`, `path` and, for user errors, `field`.

The rewording rule has a corollary for tests. Assert the message only for errors the service wrote, as `verify.sh` does for `voyage service unavailable`, which is identical on both stacks because both are constructed in the example. Never assert the text of a request error: the two engines word them differently, as the earlier lab and nullability-propagation runs showed, and the example asserts their shape.

## On the wire

Start the stack. Quarkus is on `8190` and Python on `8191`.

```bash
docker compose -f examples/09-error-handling/compose.yaml up -d --build
Q() { curl -s localhost:${2:-8190}/graphql -H 'Content-Type: application/json' -d "$(python3 -I -c 'import json,sys; print(json.dumps({"query": sys.argv[1]}))' "$1")"; echo; }
```

An exposed error first. The voyage service is down for `V404X`:

```bash
Q '{ cargo(trackingId: "JKL567") { trackingId itinerary { legs { loadLocation { unLocode } voyage { number } } } } }'
```

```json
{"errors":[{"message":"voyage service unavailable","locations":[{"line":1,"column":89}],"path":["cargo","itinerary","legs",0,"voyage"],"extensions":{"code":"SERVICE_UNAVAILABLE"}}],"data":{"cargo":{"trackingId":"JKL567","itinerary":{"legs":[{"loadLocation":{"unLocode":"USNYC"},"voyage":null}]}}}}
```

Python sends the same error with `data` first. A masked error:

```bash
Q '{ cargo(trackingId: "PQR234") { trackingId delivery { transportStatus } } }'
docker compose -f examples/09-error-handling/compose.yaml logs quarkus | grep handling-primary-3
```

```json
{"errors":[{"message":"Internal server error.","locations":[{"line":1,"column":44}],"path":["cargo","delivery"],"extensions":{"code":null}}],"data":{"cargo":null}}
```

Python answers `{"data":{"cargo":null},"errors":[{"message":"Internal server error.","locations":[{"line":1,"column":44}],"path":["cargo","delivery"]}]}`: the same message and path, and no `extensions` key. The `grep` finds the exception in the Quarkus log; use the service name `python` for the other stack, where the line comes from the `strawberry.execution` logger. The partial-data query is the one above, and the request error and the status codes follow:

```bash
Q '{ cargo(trackingId: "ABC123") { weight } }' 8191
for a in application/json application/graphql-response+json; do
  curl -s -o /dev/null -w "%{http_code} %{content_type}\n" localhost:8190/graphql -H "Accept: $a" \
    -H 'Content-Type: application/json' -d '{"query":"{ cargo(trackingId: \"ABC123\") { weight } }"}'
done
```

```text
{"data":null,"errors":[{"message":"Cannot query field 'weight' on type 'Cargo'.","locations":[{"line":1,"column":33}]}]}
200 application/json
200 application/graphql-response+json
```

Port `8191` answers `200 application/json` for both headers. Messages, timestamps and log lines differ on every run. The paths, codes, counts and statuses do not.

| Check | Expected |
|---|---|
| `JKL567` itinerary legs with `loadLocation` and `voyage` | 1 error, path `["cargo","itinerary","legs",0,"voyage"]`, message `voyage service unavailable`, `extensions.code` `"SERVICE_UNAVAILABLE"`, with `message`, `locations` and `path`; `voyage` null, `loadLocation` `USNYC` |
| `PQR234` `cargo { trackingId delivery { transportStatus } }` | `data.cargo` null; 1 error, path `["cargo","delivery"]`, message `Internal server error.`; no `handling-primary-3`, `IllegalStateException`, `RuntimeError` or `com.patterncatalyst` in the response; `handling-primary-3` in the service log |
| the same, `extensions.code` | Quarkus JSON `null`; Python has no `extensions` key |
| three aliases `ok`, `outage`, `bug` | 2 errors with paths `["outage","itinerary","legs",0,"voyage"]` and `["bug","delivery"]`; `ok.trackingId` `ABC123`; `bug` null; `data` keys `ok,outage,bug` |
| `MNO901` itinerary legs `loadLocation` | `itinerary` null; 1 error, path `["cargo","itinerary","legs",0,"loadLocation"]`; message contains `loadLocation` on Quarkus, equals `Internal server error.` on Python |
| `{ cargo(trackingId:"ABC123"){ weight } }` | errors with `message` and `locations` and no `path`; no `data` (Python sends `"data":null`); no source call |
| status and media type, request error and execution error (the draft asks for a 4xx and for 294) | `200 application/json` for `Accept: application/json`; for `Accept: application/graphql-response+json`, Quarkus `200 application/graphql-response+json`, Python `200 application/json` |
| `registerHandlingEvent` LOAD at `DEHAM` on `V999X` | no `errors`; `userErrors` `[{"code":"UNKNOWN_VOYAGE","field":["input","voyageNumber"]}]`; `handlingEvent` null; no `appendEvent` call |
| `a: voyage("V404X")`, `b: voyage("V100S")` | 1 error, path `["a"]`, code `SERVICE_UNAVAILABLE`; `a` null; `b.number` `V100S` |
| scalars and live schema | `SCALAR` and the `specifiedByURL` values from the canonical SDL; conforms to `contracts/schema/` |

`bash examples/09-error-handling/verify.sh` runs the whole sequence on both stacks and prints `PASS` only when both hold.

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>Error handling is where the <em>aggregation across sources</em> axis of the decision framework gets its operating rule: when one of several owners fails, the response keeps the rest and says which part is missing, with a path and a code a client can act on. The <em>contract and evolution style</em> axis decides the shape. Codes are contract and messages are not, so a new <code>extensions.code</code> value is a change to review like an enum value, and a payload <code>userErrors</code> list can grow where a result union cannot gain a member safely. The <em>operational and security cost</em> axis decides the masking and the monitoring: an allowlist hides every unexpected exception by default and keeps the detail in the log, and because both stacks answer <code>200</code> under both media types, where the GraphQL-over-HTTP draft recommends a <code>4xx</code>, the monitor counts <code>errors</code> entries by code. The tracking view therefore exposes outages with <code>SERVICE_UNAVAILABLE</code>, masks everything else as <code>Internal server error.</code>, keeps expected domain failures in <code>userErrors</code>, and treats the status code as no signal at all.</p></div>

## Review

- A request error means no resolver ran; an execution error leaves partial `data` plus a `path` to the field that failed.
- An error's `message`, `locations`, `path`, and `extensions` each carry a different kind of information, and a client can rely only on `path` and `extensions.code`.
- An unexpected exception is masked as `Internal server error.` behind an allowlist, while a known outage like `SERVICE_UNAVAILABLE` reaches the client through `extensions.code`.
- The null in `data` lands at the nearest nullable ancestor, which can sit above the field named in the error's `path`.
- Top-level `errors`, payload `userErrors`, and a result union are three ways to report failure, each suited to a different kind of failure.

## Where this goes next

This chapter gave failures a contract: the difference between request and execution errors, the parts of an error, partial data with a path to each hole, a code vocabulary, masking by allowlist on both stacks with the detail kept in the log, the status codes the GraphQL-over-HTTP draft asks for against the `200` the stacks send, and the choice between top-level errors, payload `userErrors` and a result union.

Schema design patterns come next, including the `Node` interface and its `nodes` field. The breaking-change gate treats a new `extensions.code` value or a new union member as an evolution decision. Relay-style pagination reuses the exposed and masked machinery from this example: its connection arguments raise `BAD_USER_INPUT` for an invalid cursor and a page size outside `0..50`, and its booking outage for `GHI345` is a `SERVICE_UNAVAILABLE`. Later, the error count becomes a metric.

For the formal definitions, read "Response" with its "Errors" and "Error Result Format" sections, and "Handling Execution Errors", in the [GraphQL specification](https://spec.graphql.org/), and "Status Codes" with the response media types in the current working draft of the [GraphQL-over-HTTP specification](https://http-spec.graphql.org/draft/). The framework behaviour is in the Quarkus [SmallRye GraphQL guide](https://quarkus.io/guides/smallrye-graphql), where the error settings are documented, and in the Strawberry documentation under "Dealing with errors" and the `MaskErrors` extension. Artur Czemiel's *GraphQL Best Practices* covers the same ground in its treatment of error descriptions, and Samer Buna's *GraphQL in Action* gives the user-error context in "Implementing mutations"; both are listed on the [Bibliography](../../bibliography/) page.

## For deeper coverage

- [GraphQL specification: Response, Errors, Error Result Format, Handling Execution Errors](https://spec.graphql.org/): the anatomy of an error and the partial-data model.
- [GraphQL-over-HTTP working draft: Status Codes](https://http-spec.graphql.org/draft/): what a request error and an execution error should answer with, versus what both stacks send.
- *Cloud Native Design Patterns*, "API Error Handling" (Appendix E): the broader error-contract patterns this chapter's exposed/masked split is one instance of.
- Artur Czemiel, *GraphQL Best Practices* (Packt, 2024): error descriptions and message design.
- Samer Buna, *GraphQL in Action* (Manning, 2021): the user-error context in "Implementing mutations."
