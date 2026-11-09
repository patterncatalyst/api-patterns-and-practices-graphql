---
title: "Error handling"
order: 9
part: "Reliability: Errors & Partial Results"
description: "How GraphQL reports failure: request errors against execution errors, the anatomy of an error, partial data, a stable extensions.code vocabulary, masking unexpected failures on both stacks, status codes and media types, and the choice between errors[], payload userErrors and result unions."
duration: "13 min read"
---

## Learning objectives

By the end of this chapter you can:

- Distinguish a request error (no resolver ran) from an execution error (partial `data` plus a `path` to the failure).
- Read an error's `message`, `locations`, `path`, and `extensions` and know which parts a client may rely on.
- Mask an unexpected exception as `Internal server error.` behind an allowlist, while routing an outage like `SERVICE_UNAVAILABLE` to the client via `extensions.code`.
- Explain why the null in `data` can land at a different point than the error's `path`, depending on nullability.
- Weigh top-level `errors`, payload `userErrors`, and a result union as three ways to report failure, and justify which one a given failure belongs in.

## Why this matters

A failure needs a contract: what an error contains, which parts a client can rely on, and which parts the server keeps to itself. The tracking view fails in three ways, and both stacks answer them with the same shape. `JKL567` sails on a voyage whose service is down, `MNO901` loads at a location code the location service doesn't know, and `PQR234` makes the handling service fail with an unexpected exception that carries an internal shard name. An outage is an exposed error with a code, anything unexpected is masked as `Internal server error.`, and the detail goes to the server log.

## Two kinds of failure, one array

The specification separates failures by when they happen. A **request error** occurs before execution begins: the document doesn't parse, fails validation, a variable doesn't coerce, or the operation can't be selected. No resolver runs, so there is no `data` entry (Python sends `"data":null`). An **execution error** occurs while a resolver runs. Execution continues, so the response carries `data` with a null where the field failed, and the error carries a `path` to that field.

Both arrive in the same top-level `errors` array, so the array alone doesn't tell a client what happened. The shape does. Errors with no `data` mean the request was rejected and nothing was fetched. Errors beside `data` mean the server did what it could and part of the answer is missing. A third outcome has no `errors` at all: a mutation's `userErrors` are ordinary data in a successful response.

{% include excalidraw.html file="09-error-taxonomy" alt="Three horizontal lanes. A request error runs through parse, validate, coerce variables and select operation, and exits to errors with locations and no path, no data (Python sends data null), and no resolver ran. An execution error shows a resolver that raises either an exposed error or an unexpected one that is masked, and both exit to data plus errors with a path, where the null lands at the nearest nullable ancestor. A domain failure shows a mutation validating its input and exiting to data with userErrors and no errors key. All three answer 200 on both stacks." caption="Figure 9.1: Three kinds of failure and the response each produces. Only the first happens before a resolver runs." %}

The origin decides what a client does next. A request error is a defect in the client: retrying the same document fails the same way. An execution error may be transient, as an outage often is, so a retry can succeed. A domain failure is neither: the input was understood and refused, and the user can correct it.

## Anatomy of an error

Each entry in `errors` is a map with these keys:

- `message` is a string for a developer. Its wording belongs to the engine or the resolver, and clients must not parse it.
- `locations` is a list of line and column pairs into the request document. Request errors and most execution errors have it. graphql-java's own null-in-a-non-null-field error arrives with a `path` and no `locations`, so a client treats the key as optional.
- `path` is the response path of the field that failed. It exists only for execution errors. Each step is a response key (the alias when the selection has one) or a list index, and an index is a JSON number: `0`, not `"0"`. `bug: cargo(...)` that fails at `delivery` reports `["bug","delivery"]`.
- `extensions` is a map the server may fill with anything. It is the only place for custom keys, because a future edition of the specification may claim any other key.

Request errors come from the engine's validation rules or coercion, in its own words. An unknown field gives `Cannot query field 'weight' on type 'Cargo'.` on Strawberry and `Validation error (FieldUndefined@[cargo/weight]) : Field 'weight' in type 'Cargo' is undefined` on Quarkus. Assert structure and codes, never request-error wording.

The order of entries in `errors` carries no meaning, so a client finds an error by its `path` and not by position.

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

{% include excalidraw.html file="09-partial-data-errors" alt="Two panels. Left, the data tree with three branches: ok is a solid box with the tracking id resolved, outage shows a solid cargo box and a dashed null voyage, and bug is a dashed null cargo. Right, two error boxes. The outage error has code SERVICE_UNAVAILABLE, message voyage service unavailable and path outage, itinerary, legs, zero, voyage. The bug error has code null on Quarkus and no extensions on Python, message Internal server error. and path bug, delivery. An arrow runs from each path to its hole." caption="Figure 9.2: The response to the three-alias query. A path names where it broke, and the null lands at the nearest nullable ancestor." %}

A client with one request per screen section renders what arrived and marks the missing parts. A client that treated any entry in `errors` as a failed request would throw away two usable answers. Each alias sits under its own nullable root field, so one failure can't take another alias with it.

## Where the null lands

The error's `path` names the field that failed. The null goes where the type system allows it. `Leg.voyage` is nullable, so the failure and the hole coincide at `["cargo","itinerary","legs",0,"voyage"]`. `Cargo.delivery` is non-null, so the engine nulls the nearest nullable ancestor instead, which is `cargo`. The error still says `["bug","delivery"]`, and a client that looks for a null at that path finds the parent null.

`MNO901` combines both rules. The location source answers null for `XXBAD`, `Leg.loadLocation` is non-null, `legs` is a non-null list of non-null legs, and `Itinerary.legs` is non-null. The null climbs to `Cargo.itinerary`, the first nullable position on the way up. One error, one hole, and `trackingId` is still `MNO901`. The error count is one however far the null travels.

## A code vocabulary in extensions

A client that switches on a message breaks whenever someone rewords it. A client that needs to act on a failure, say by retrying, needs `extensions.code`, a short string from a vocabulary the service owns and documents.

| `extensions.code` | Raised for | Message | Exposed |
|---|---|---|---|
| `SERVICE_UNAVAILABLE` | a source outage (`V404X`) | `voyage service unavailable` | yes |
| none | anything unexpected | `Internal server error.` | masked |

Codes are contract and messages are not. Adding a code follows the evolution rules for enum values: safe for a client with a default branch, breaking for one without. Cursor pagination adds `BAD_USER_INPUT` for cursors that pass coercion and are still invalid.

A client reads an error in this order:

1. Is `data` absent? The request was rejected and nothing was fetched. The fix is in the client.
2. Otherwise find the hole by `path` and decide per entry. `SERVICE_UNAVAILABLE` earns a bounded retry or a degraded rendering. A masked error with no code gets a generic apology while the server log keeps the exception, stack and time. An unknown code falls to the same generic branch, which is what makes it safe for the service to add a code later.

Request errors carry no code. The engines write them before any resolver runs, in their own words, and a client branches on their structure: errors present and no `data`.

## Masking what clients must not see

An unexpected exception carries whatever its author put in the message: a table name, a shard, a host, a stack. For `PQR234` it is `handling projection corrupted on shard handling-primary-3`. Showing that exposes topology and invites probing, and the client can't fix a corrupted shard. The client gets a generic message and the operator gets everything in the server log.

Both frameworks implement this as an allowlist. Nothing is shown unless the service listed it, so an exception class added next year is masked by default.

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
        # graphql-core copies a dict ``extensions`` from the original error
        # onto the GraphQLError it builds.
        self.extensions = {"code": self.code}


class SourceUnavailable(ExposedError):
    """A source cannot answer (the outage seeds: voyage V404X)."""

    code = "SERVICE_UNAVAILABLE"
```

SmallRye hides the message of every unchecked exception by default. `show-runtime-exception-message` lists the classes whose messages are shown, which makes it the allowlist, and `default-error-message` sets the replacement. `@ErrorCode` sets `extensions.code`.

```properties
quarkus.smallrye-graphql.show-runtime-exception-message=com.patterncatalyst.shipping.tracking.SourceUnavailableException
quarkus.smallrye-graphql.default-error-message=Internal server error.
quarkus.smallrye-graphql.error-extension-fields=code
```

Strawberry ships a `MaskErrors` schema extension that replaces the message of the errors a predicate selects. The predicate masks every error whose original exception isn't an `ExposedError`, so the class hierarchy is the allowlist.

```python
def should_mask(error: GraphQLError) -> bool:
    """Mask an error unless a resolver raised an ``ExposedError``.

    An error with no ``original_error`` came from the engine itself (a request
    error: parse, validation, coercion) and keeps its message. An error whose
    ``original_error`` is anything but an ``ExposedError`` is an unexpected failure, or
    a null in a non-null field (a ``TypeError``), and is masked.
    """
    return error.original_error is not None and not isinstance(error.original_error, ExposedError)
```

```python
schema = strawberry.Schema(
    query=Query,
    mutation=Mutation,
    config=StrawberryConfig(scalar_map=SCALAR_MAP),
    extensions=[MaskErrors(should_mask_error=should_mask, error_message="Internal server error.")],
)
```

`MaskErrors` rebuilds a masked error without its `extensions`, so a masked error carries no code. A `GraphQLError` raised directly is masked too, because it isn't an `ExposedError`: a resolver raises a subclass of `ExposedError` for anything a client should read.

{% include excalidraw.html file="09-error-masking" alt="A left to right flow. A source throws an exception, the resolver doesn't catch it, and the engine builds an error holding the path, the message and the original exception. The error passes an allowlist box that names the SmallRye show-runtime-exception-message setting and the Strawberry should_mask predicate. On the list leads to an exposed box where the client gets the message and the code SERVICE_UNAVAILABLE. Anything else leads to a masked box where the client gets Internal server error, with no detail and no class name. A dashed arrow from the engine error leads down to a server log box that keeps the full message, the stack, the time and the shard name." caption="Figure 9.3: Masking is an allowlist. The client sees only what the service listed; the log always sees everything." %}

The log half needs the same attention. Strawberry logs the original exception, with its traceback, through the `strawberry.execution` logger before `MaskErrors` builds the replacement. SmallRye logs it when `print-data-fetcher-exception` is on. The shard name must be in the service log after a masked request and absent from the response.

SmallRye's built-in providers would add an `exception` field and a code for every exception, so the service replaces them with one that supplies `extensions.code` only for exceptions annotated `@ErrorCode`. It is registered through SmallRye's `ErrorExtensionProvider` SPI, listed in `META-INF/services/io.smallrye.graphql.api.ErrorExtensionProvider`, and the built-in provider file is removed with `quarkus.class-loading.removed-resources`.

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

The provider file removal sits next to `print-data-fetcher-exception`, the setting that sends the original exception to the log:

```properties
# Remove SmallRye's built-in providers;
# DeclaredErrorCodeProvider is the only source of extensions.code.
quarkus.class-loading.removed-resources."io.smallrye\:smallrye-graphql"=META-INF/services/io.smallrye.graphql.api.ErrorExtensionProvider
quarkus.smallrye-graphql.print-data-fetcher-exception=true
```

A masked error on Quarkus carries `"code": null` and on Python no `extensions`; a client reads both as no code. The removal names a file inside the SmallRye jar, so check it after a SmallRye upgrade.

A null in a non-null field splits the stacks the same way. On Python the `TypeError` behind a null `loadLocation` is an unexpected exception, so the client reads `Internal server error.`. On Quarkus the error is graphql-java's own, not a fetch exception, so it is shown: the message names the field and the path, and the extension is `classification`. Both stacks null the same `itinerary`.

## Status codes and media types

The GraphQL-over-HTTP working draft asks for a `4xx` or `5xx` on a result with no `data` (`400` for a parse failure, `422` for validation and coercion). When `data` is present beside `errors`, the status must be `2xx`. The draft recommends `294` for that case, only alongside `application/graphql-response+json`: a custom "Partial Success" code outside the IANA registry that clients unaware of it treat as `200`.

Both stacks answer plain `200` for a request error and an execution error, under either `Accept` header. They differ in the media type. Quarkus echoes `application/graphql-response+json` when asked for it, and Strawberry always answers `application/json`. A client includes `application/graphql-response+json` in `Accept`, and `application/graphql-response+json, application/json;q=0.9` is the safe form when unsure.

Operations feel the consequence. A latency-and-status dashboard sees neither failure, and nothing separates a partial answer from a clean one. A monitor has to count entries in `errors`, split by `extensions.code` and by operation.

## Three envelopes for failure

A mutation returns a domain failure as `userErrors`: an unknown voyage comes back as `[{"code":"UNKNOWN_VOYAGE","field":["input","voyageNumber"]}]` with no `errors` key, a null `handlingEvent` and no write. A third envelope is a union of the mutation's outcomes, where the failure is a type:

```graphql
union RegisterHandlingEventResult = RegisterHandlingEventSuccess | ValidationFailed

type ValidationFailed {
  code: UserErrorCode!
  field: [String!]!
  message: String!
}
```

This is a sketch, not part of the served schema.

{% include excalidraw.html file="09-failure-shapes" alt="Three columns show one failure, an unknown voyage, in three envelopes. Top-level errors: an errors entry with a message and extensions code and a null data, because the non-null payload nulls the whole data field; the client branches on errors being present and then on the code, and monitors count it as a failure. Payload userErrors, which the tracking view serves: data with a null handlingEvent and a userErrors entry with code UNKNOWN_VOYAGE and a field path; the client branches on userErrors being non-empty and no errors key appears. Result union: a ValidationFailed member selected by typename; the client branches on typename with an inline fragment per member, and adding a member is a dangerous change." caption="Figure 9.4: One failure in three envelopes. The tracking view serves the middle shape and sketches the union." %}

| | Top-level `errors` | Payload `userErrors` | Result union |
|---|---|---|---|
| Fits | what a user can't fix: outages, bugs | expected, user-correctable failures | expected failures with distinct shapes |
| Client branches on | `errors` present, then `extensions.code` | `userErrors` non-empty | `__typename`, one inline fragment per member |
| Adding a case | a new code (review like an enum value) | a new `UserErrorCode` value | a new member: a dangerous change |
| Monitors count it | yes | no | no |

A union is exhaustive: a client that selects `... on` for every member gets a compile-time error from its code generator when the server adds one. That's also the cost, because a client with no default branch breaks. A union makes every outcome a `__typename` branch, where a payload keeps the common path flat: `handlingEvent` is there on success, `userErrors` is an empty list, and a client that ignores the list still renders. A payload also keeps one place for a list of failures, where a union member holds one unless the type wraps a list.

The tracking view keeps payload `userErrors` for expected, user-correctable failures, top-level `errors` for everything a user can't fix, and a code vocabulary for the second kind. A payload that can grow is cheaper to evolve than a union that can't gain a member safely, and keeping user mistakes out of `errors` keeps the failure count meaningful.

## What a message should say

A message is read by a developer with a request in front of them and sometimes, carelessly, by an end user. It says what happened to this request in domain terms: `voyage service unavailable`, `No voyage has number V999X.`. It carries no host names, class names, SQL, shard names or stack, and it doesn't change meaning between releases, because someone will match on it anyway. Everything a machine needs is in `code`, `path` and, for user errors, `field`. Test the message only for errors the service wrote.

> **🤖 Explore with your agent**
>
> "In `examples/09-error-handling/`, add a `RATE_LIMITED` code: a new `RateLimited` subclass of `ExposedError` in `python/app/errors.py` and a `@ErrorCode("RATE_LIMITED")` exception listed in `show-runtime-exception-message` for Quarkus. Make the location source raise it for `XXBAD`. Keep every other exception masked as `Internal server error.`, and tell me which of `errors`, `userErrors` or a union each of `RATE_LIMITED`, an unknown voyage and a corrupted projection belongs in."
>
> Check: query `cargo(trackingId: "MNO901")` on both stacks and confirm the new error has `extensions.code` `RATE_LIMITED` with its own message while `PQR234` still returns `Internal server error.`.

## Build, run, observe

Quarkus is on `8190` and Python on `8191`.

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

Python answers `{"data":{"cargo":null},"errors":[{"message":"Internal server error.","locations":[{"line":1,"column":44}],"path":["cargo","delivery"]}]}`: the same message and path, and no `extensions` key. The `grep` finds the exception in the Quarkus log; use the service name `python` for the other stack. Then a request error and the status codes:

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

Port `8191` answers `200 application/json` for both headers.

`bash examples/09-error-handling/verify.sh` runs the whole sequence on both stacks and prints `PASS` only when both hold. Experiments:

- **Run the three-alias query.** Two errors with paths `["outage","itinerary","legs",0,"voyage"]` and `["bug","delivery"]`, `ok.trackingId` is `ABC123`, `bug` is null.
- **Query `MNO901` itinerary legs `loadLocation`.** `itinerary` is null with one error at `["cargo","itinerary","legs",0,"loadLocation"]`. The message names `loadLocation` on Quarkus and is `Internal server error.` on Python.
- **Ask for `a: voyage(voyageNumber: "V404X")` and `b: voyage(voyageNumber: "V100S")`.** One error at `["a"]` with code `SERVICE_UNAVAILABLE`, `a` null, and `b.number` `V100S`.
- **Register a `LOAD` at `DEHAM` on `V999X`.** No `errors`; `userErrors` holds `UNKNOWN_VOYAGE` at `["input","voyageNumber"]`, and no `appendEvent` runs.

> **Decision**
>
> When one of several owners fails, keep the rest of the response and say which part is missing, with a `path` and an `extensions.code` a client can act on. Codes are contract and messages are not, so review a new code like an enum value. Expose outages as `SERVICE_UNAVAILABLE`, mask everything else as `Internal server error.` through an allowlist and keep the detail in the log, return expected domain failures as `userErrors`, and count `errors` entries by code, because the status code carries no signal on either stack.

## For deeper coverage

- [GraphQL specification: Response, Errors, Error Result Format, Handling Execution Errors](https://spec.graphql.org/): the anatomy of an error and the partial-data model.
- [GraphQL-over-HTTP working draft: Status Codes](https://http-spec.graphql.org/draft/): what a request error and an execution error should answer with, versus what both stacks send.
- The Quarkus [SmallRye GraphQL guide](https://quarkus.io/guides/smallrye-graphql) documents the error settings; the Strawberry documentation covers "Dealing with errors" and the `MaskErrors` extension.
- *Cloud Native Design Patterns*, "API Error Handling" (Appendix E): the broader error-contract patterns the exposed/masked split is one instance of.
- Artur Czemiel, *GraphQL Best Practices* (Packt, 2024): error descriptions and message design.
- Samer Buna, *GraphQL in Action* (Manning, 2021): the user-error context in "Implementing mutations."
- The [Bibliography](../../bibliography/) page lists the books.
