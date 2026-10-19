---
title: "The final project"
order: 27
part: "Running It & the Final Project"
description: "The whole tracking view as one system: the complete schema with subscriptions over WebSocket and SSE, query limits, Keycloak tokens with operation, object and field authorization on every path, introspection on internal instances only, one edge in front, telemetry by trace id and a k6 load, the same images in every tier."
duration: "15 min read"
---

## Learning objectives

By the end of this chapter you can:

- Order a request's defences so the cheapest refusal (TLS, body size, cost budget) runs before an expensive one, like an authorization lookup.
- Wire Keycloak bearer tokens through operation, object, and field authorization on queries, subscriptions, and a plain `/events/` feed.
- Serve one image as a public instance with introspection off and an internal instance with it on, selected by an environment key.
- Keep a subscription's one-time admission check (`IsAuthenticated`, `CanWatchCargo`) separate from its per-event field check (`registrationTime`).
- Run the same two images unchanged across a Compose tier, a Helm chart on minikube, and an OpenShift Local wrapper chart, changing only configuration values.

## Why this matters

Chapter 25 put the tracking view behind an edge and gave it a tier to live in. Chapter 26 moved that tier onto a cluster. Neither chapter changed what the service says. This one does the opposite: the infrastructure stays as it was, and the service gets everything the earlier chapters built, all at once. The schema is complete, `Subscription` included. Requests carry tokens, and what a caller may see depends on who it is. A document that costs too much is refused before a source is asked. Introspection answers on the instances that developers use and not on the ones that clients reach.

The code is in `examples/27-final-project/`. It starts from the Chapter 25 example and ports in what Chapters 21, 14, 18 and 17 added, in that order, with `verify.sh` run after each port. The canonical SDL does not change, and the chapter ends with the check that proves it: both stacks serve exactly the schema in `contracts/schema/`. Nothing in this chapter is a new technique. The work is in making the techniques coexist, and in seeing where one of them has to know about another.

## The system

Figure 27.1 shows the compose project. The public instances of Quarkus and Python are the ones a client reaches, through the edge, and they publish nothing. Each stack also runs a second time from the same image as an internal instance, with introspection on, published on `127.0.0.1` only. Keycloak issues the tokens. The Grafana LGTM image receives the telemetry. Two more services sit behind compose profiles and start only when a script runs them: a subscription client and the k6 runner.

{% include excalidraw.html file="27-final-architecture" alt="A band for the compose project holds a client on the left that sends a bearer token and a traceparent over TLS 1.3 to the edge, labelled Chapter 25, which proxies slash graphql, the WebSocket upgrade and slash events to the public instances of Quarkus and Python, labelled Chapters 14, 17, 18 and 21, with introspection off and no published port. A dashed arrow joins the public instances to the internal instances, which run the same images with introspection on and publish on 127.0.0.1 ports 8372 and 8373. Amber arrows run from the public instances to Keycloak 26.8.1, labelled Chapter 18, and from the application instances to lgtm 0.37.0, labelled Chapters 19 and 25. Below sit the client profile, labelled Chapter 21, the load profile with k6 v2.3.0, labelled Chapter 23, and the contracts schema directory that the internal instances are compared with. A dashed box lists the chapters that stay out." caption="Figure 27.1 — The final project's compose tier. Each component comes from an earlier chapter; this chapter adds the wiring between them." %}

The table in the example's README lists what each chapter contributes. The short form is a sentence per chapter. Chapter 13 supplies the seed, the batched sources and the source-call log. Chapter 14 supplies the depth, token, alias and cost limits. Chapter 17 supplies the switch that turns introspection off. Chapter 18 supplies Keycloak and the three authorization rules. Chapters 19 and 24 supply the spans, the metrics and `extensions.traceId`. Chapter 21 supplies the subscription and the event feed. Chapter 23 supplies the k6 image and the two documents the load runs. Chapter 25 supplies the edge, the networks, the health split and the limits.

Each ported file keeps the header comment of the chapter it came from, so the origin of a class reads from its first line. The ports changed little in the code that was already there. Chapter 25's `schema.py` gained a `Subscription` type and a longer list of extensions, and its context gained an identity. The work that needed care was in the seams, and the sections below follow them.

## What stays in its own chapter

Four topics stay out, and one paragraph each says why. Persisted documents (Chapter 15) are a deployment decision: an allowlist of operations is built from a client's documents at release time, and a reader adds it with the pieces of that chapter when the clients are known. Caching (Chapter 16) does not combine with this example. A response that depends on the caller's token is private, so a shared cache must not hold it, and the per-shipper answers here would only ever produce misses. Federation (Chapter 20) describes a different topology, many services behind a gateway, where this example is one service. Client integration (Chapter 22), the test suites of Chapter 23 and the dev instances of Chapter 24 serve people who change the code. The load run reuses Chapter 23's k6 runner and its two documents instead of repeating the suites, and the seeded fault of Chapter 24 has no place in a system that is meant to be correct.

## A request's defences, in order

A request that reaches the tier meets a fixed sequence of decisions, and each decision has its own answer when it refuses. Figure 27.2 lays the sequence out, with the answer each defence gave in the run that `verify.sh` records.

{% include excalidraw.html file="27-request-defences" alt="Three horizontal bands show the order of the defences. The first band, before GraphQL runs, holds the TLS 1.3 listener, the 64k body limit and token validation, with a dashed arrow labelled refused to a dark box listing a failed TLS 1.2 handshake, a 413 status, and a 401 status with a WWW-Authenticate Bearer challenge. The second band, before any resolver runs, holds the token limit of 5000, the depth and alias rules and the cost budget of 1000, with a dashed arrow labelled refused to a dark box stating a 200 response with no data, the message maximum query complexity exceeded 7651 over 1000, and zero source calls. The third band, while the operation runs, holds the operation rule, which answers UNAUTHENTICATED at the root field, the object rule, under which a cargo of another shipper is null, the field rule, which answers FORBIDDEN at registrationTime, the batched sources with eight calls on Quarkus and six on Python, and error masking with extensions.traceId. Amber arrows join the bands." caption="Figure 27.2 — The defences in the order a request meets them, and the answer each gives. The values are the ones verify.sh asserts on both stacks." %}

The first three are the edge's and the identity layer's. A TLS 1.2 client cannot finish the handshake. A body over 64k gets `413` from nginx, and the backend's source-call log stays empty because the request never arrived. A token for another audience gets `401` with a `WWW-Authenticate` challenge, before any GraphQL runs. Quarkus answers with `Bearer` and an empty body, Python with `Bearer error="invalid_token"` and a small JSON body, and the script asserts each stack's own form.

The next three belong to the document, and they run before any authorization rule. Chapter 14's limits read the document and the variables, never the caller, so an anonymous request with a document priced at 7,651 against a budget of 1,000 is refused the same way an operator's would be: status `200`, no `data`, one error that states the price, and no source call. The depth limit and the alias limit read the same way. The two stacks count depth differently, one counting a root field as 1 and the other as 0, so their limits are 15 and 14 and the messages differ; both refuse the same documents.

The last group runs inside the operation. An anonymous caller reaching `cargo` gets `UNAUTHENTICATED` at the root field's path. A shipper asking for a cargo that another shipper owns gets `null` and no error, the same answer as for an unknown id, so the response does not say which tracking ids exist. A shipper asking for `registrationTime` gets `FORBIDDEN` at that field's path and a null edge node, while the rest of the page survives. What remains goes to the sources in the batched calls of Chapter 13: eight on Quarkus, six on Python, with the same keys. A failure that is not an exposed error is masked, and every error that reaches a client carries the trace id that finds it in Tempo and Loki.

The order matters in one direction in particular. The cost check runs before the authorization rules, so a refusal for cost needs no knowledge of who the caller is. If the order were reversed, every over-budget request would first cost an ownership lookup in the booking source. The edge's checks come first for the same reason: the cheapest refusal is the one made before the application is involved.

## Identity on every path

The edge passes `Authorization` through unchanged, which is all it does with identity. Validation stays in the stacks, where Chapter 18 put it. Quarkus validates with `quarkus-oidc` in service mode. Python validates with PyJWT and a `PyJWKClient` that fetches Keycloak's keys. Both read the keys over the backend network, from `keycloak:8080`, and both compare the token's issuer with a pinned value.

Those two addresses differ because they do different jobs. A token carries the address its client fetched it from, `http://localhost:8374/realms/shipping`, because that is where Keycloak is published. The stacks cannot reach that address from inside the network. The back channel is the service name; the issuer is a string to compare. In the example both are configuration, which is what lets one image run in three tiers:

{% include codetabs.html langs="Quarkus|Python" %}

```properties
QUARKUS_OIDC_AUTH_SERVER_URL=http://keycloak:8080/realms/shipping
QUARKUS_OIDC_TOKEN_ISSUER=http://localhost:8374/realms/shipping
```

```properties
TRACKING_OIDC_JWKS_URL=http://keycloak:8080/realms/shipping/protocol/openid-connect/certs
TRACKING_OIDC_ISSUER=http://localhost:8374/realms/shipping
```

A cluster changes the two values and nothing else, and so does an OpenShift Local project in Appendix A. The environment contract in the README lists every key that differs by stack, and the rule of Chapter 25 holds: the application has no code path that depends on the tier.

## Real time through the edge

A subscription arrives as a WebSocket upgrade, so the edge has two jobs it did not have in Chapter 25. It forwards the upgrade headers, and it holds an idle connection open. The first needs the `Upgrade` and `Connection` map that Chapter 25's configuration already carried unused. The second is a longer read timeout on the proxied locations, because a subscriber is silent between events. The event feed is a long response and needs its own location:

```nginx
        location = /graphql {
            proxy_pass $backend;
        }
        location /events/ {
            proxy_pass $backend;
            proxy_buffering off;
        }
```

`proxy_buffering off` lets each event reach the client as it is written, and `$backend` is the variable form of the upstream, which nginx resolves per request through Docker's DNS. The same shape in the cluster resolves through the Service name.

The token travels on the upgrade request. Both frameworks read it there: Quarkus authenticates the upgrade like any HTTP request, and Python reads the `Authorization` header from the WebSocket connection in the same dependency that reads it from a `Request`. A token that does not validate refuses the upgrade, as it refuses a query. With no token the client connects as an anonymous caller, and the operation rule decides what happens next.

Figure 27.3 follows one registration through the system. The operator `ops` sends `REG_F1`, an `UNLOAD` of `ABC123` at Hamburg, through the edge. The handling store records it as `evt_10` and broadcasts it, and each subscriber hears it under its own rights.

{% include excalidraw.html file="27-subscription-path" alt="Four clients on the left connect to the edge: ana subscribing over wss with a bearer token, bo doing the same, ana reading the plain event feed from the event id evt_9, and ops sending the mutation REG_F1. The edge, which keeps the Authorization header and the upgrade headers, leads to an admission box that checks once that the caller is signed in and may see ABC123, to a dark box where bo receives an error message with the code FORBIDDEN and no event follows, and to the feed box that answers 401, 403 or 200 and replays evt_10 after evt_9. The mutation reaches the handling store, which stores evt_10 and broadcasts it. Two amber boxes on the right show the next message to ana, a fresh execution with Hamburg, IN_PORT and registrationTime FORBIDDEN, and the next message to ops, the same selection with registrationTime as a value. Below them are the frames of ana's run and a TrackCargo query that then says IN_PORT." caption="Figure 27.3 — One registration, heard by each subscriber under its own rights. Admission happens once, when the subscription starts; field authorization happens again on every event." %}

Two kinds of rule apply, and they apply at different times. The operation rule and the object rule are decided once, when the subscription starts: the caller must be signed in, and must be allowed to see the cargo it names. On Python they are permission classes on the field, `IsAuthenticated` and then `CanWatchCargo`, which reuses the ownership function of Chapter 18:

```python
    @strawberry.subscription(
        description="Emits each new handling event for one cargo as it is registered.",
        # Operation and object authorization (Chapter 18), once, before the first event.
        # Field authorization (HandlingEvent.registrationTime) applies to every event.
        permission_classes=[IsAuthenticated, CanWatchCargo],
    )
```

On Quarkus the same two checks are `SubscriptionGate`, a graphql-java instrumentation installed in the chain that already carries Chapter 14's cost limit and Chapter 21's loader reset:

```java
    private void admit(TrackingId trackingId) {
        Viewer viewer = viewers.current();
        if (viewer == Viewer.ANONYMOUS) {
            throw new AuthenticationRequiredException();
        }
        if (!booking.mayWatch(trackingId.value(), viewer)) {
            throw new WatchNotPermittedException();
        }
    }
```

The gate runs while the engine creates the event stream, so a refusal reaches the client as an error message with the code, `UNAUTHENTICATED` or `FORBIDDEN`, and no event follows. Both stacks refuse an unknown cargo and another shipper's cargo with the same message, for the reason Chapter 18 gave: an error that differed would tell a caller which tracking ids exist.

The field rule is different, because it cannot be decided once. The selection set runs again for every event, and `registrationTime` is for operators. Python keeps the subscriber's identity in the connection's context, so the permission class on the field answers for the subscriber every time. On Quarkus, `SubscriberIdentity` takes the subscriber's `SecurityIdentity` when the subscription starts and delivers each event in a request context that holds it, so each event runs with the subscriber's identity. `@RolesAllowed("operator")` and the `Viewers` class then answer for the subscriber, including in the continuations that resume after a source's latency. The annotation on the field is the same one Chapter 18 used for queries.

The script proves it with a document that reaches `registrationTime` through `cargo.handlingHistory`, which sits under nullable parents. Both `cargoHandled` and `registrationTime` are non-null, so a refused field selected on the event itself would null the whole event (Chapter 4); under `handlingHistory` the null stops at the nullable edge node. For `ana`, the event arrives with two `FORBIDDEN` errors at the field's path and both history nodes null. For `ops`, the same document returns both values. One registration, three subscribers, three answers.

The plain feed applies the same rules before it starts streaming. `GET /events/cargos/ABC123` is `401` without a token and `403` for `bo`. For `ana`, a reconnect with `Last-Event-ID: evt_9` replays `evt_10`, then continues live. Python also serves GraphQL over SSE on the same path as the WebSocket, and the script runs a fourth subscriber on it. The count of live subscribers, read inside the containers, returns to zero on both channels when the clients leave.

## The complete schema

The internal instances answer introspection, and `assert_sdl_equals` compares each of them with the canonical SDL in both directions. Nothing is missing and nothing is extra: the schema that two frameworks built from annotated and decorated code is the schema in `contracts/schema/`, `Subscription` and its description included. The check ignores the framework's own additions by name, as every contract check in the book does, and one deprecation, `Itinerary.finalArrivalDate`, which the canonical file declares as a directive and the live schema reports as state. The script asserts the state with `assert_deprecated`.

The public instances answer the same request with a refusal, even for an operator. Quarkus says `Introspection has been disabled for this request`. Python says the introspection has been disabled and names the field. Chapter 17 explained why the contract needs this: a schema that clients must not be able to enumerate is still a schema the build must be able to read. One image with two kinds of instance serves both, selected by an environment key, `TRACKING_INTROSPECTION_ENABLED` on Quarkus and `TRACKING_PUBLIC` on Python, so a deployment that wants a third kind adds an instance and no code.

## Observing it

The diagnosis path of Chapter 24 survives the whole stack. The script picks a trace id, sends it in a `traceparent` header through the edge, and asks for `cargos(first: 10)` as an operator. The error at the sixth edge, the booking outage of `GHI345`, carries `extensions.traceId` equal to the id the client chose. Tempo holds the operation span under that id. The number of `source.call` spans for `getLocations` equals the number of such calls in the source-call log, which ties the trace to the batching of Chapter 13: one call for many locations shows as one span. Loki returns a record for the same `trace_id`. No span carries an attribute that holds a credential, which the script asserts by name.

Identity and telemetry meet here without conflict because each leaves the other alone. The token is validated before the operation span opens, and the span records the operation and the route, never the token or an argument value.

## Defending it under load

Chapter 23 ran k6 against the stacks directly. Here k6 runs on the backend network and reaches the edge by name, over TLS, with an operator's token. The container trusts the lab's certificate authority through `SSL_CERT_FILE`, so the run exercises the same listener a client uses. Two runs remain of the four in Chapter 23, the two that bear on defence:

- `fanout`: 80 `FanOut` requests from eight virtual users.
- `cost`: 40 `FanOut` and 40 `OverBudget` requests at the same time.

The thresholds judge correctness. No request may fail at the transport level, every check must be true, and every scheduled request must run. Latency appears in the summary and no assertion reads it. The runner prints k6's own summary object as the last line of its output, which is the shape the harness's `run_load` reads, so the library helper checks the number of completed runs and the check rate and the script adds its own reads.

The invariants come from the source-call log, as they did in Chapter 23. In `fanout`, the log holds 80 distinct request ids, each with the calls of one request, eight on Quarkus and six on Python, and each with Chapter 14's key set. Under eight concurrent virtual users no request's keys enter another's batch. In `cost`, the log holds 40 request ids, not 80, because a refused request makes no call. With a token, the over-budget document costs the system one token validation, one parse and one price calculation, and no source call.

## Three tiers, one image

`verify.sh` is the compose tier. A Helm chart runs the same three images, `gql-ch27-quarkus:1.0`, `gql-ch27-python:1.0` and `gql-ch27-client:1.0`, on the minikube profile of Chapter 26, and Appendix A wraps that chart for OpenShift Local. What changes between tiers is configuration: the issuer, the address of the identity provider, who terminates TLS, and how a client reaches the edge. Nothing changes in the code. The environment contract in the README is the list of what to set.

A service that runs the same way in a local compose project and in a cluster has put its differences where they belong, in values a platform owner can read. A service that has to be patched per tier has hidden them in the code.

## On the wire

Generate the certificates, start the project and fetch tokens from Keycloak at the address the stacks pin as the issuer:

```bash
examples/27-final-project/gen-certs.sh examples/27-final-project/certs
docker compose -f examples/27-final-project/compose.yaml up -d --build --wait
CA=examples/27-final-project/certs/ca.crt
token() { curl -s -d "grant_type=password&client_id=tracking-cli&username=$1&password=$1-fixture-pw" \
  http://localhost:8374/realms/shipping/protocol/openid-connect/token | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])'; }
ANA=$(token ana); OPS=$(token ops); BO=$(token bo)
```

An anonymous request to the Python stack, then `ana`'s page of cargos, and `bo` asking for `ana`'s cargo:

```bash
curl -s --cacert $CA https://localhost:8371/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ cargo(trackingId: \"ABC123\") { trackingId } }"}'
curl -s --cacert $CA https://localhost:8371/graphql -H 'Content-Type: application/json' -H "Authorization: Bearer $ANA" \
  -d '{"query":"{ cargos(first: 10) { totalCount edges { node { trackingId } } } }"}'
curl -s --cacert $CA https://localhost:8371/graphql -H 'Content-Type: application/json' -H "Authorization: Bearer $BO" \
  -d '{"query":"{ cargo(trackingId: \"ABC123\") { trackingId } }"}'
```

```json
{"data":{"cargo":null},"errors":[{"message":"authentication required","locations":[{"line":1,"column":3}],"path":["cargo"],"extensions":{"code":"UNAUTHENTICATED","traceId":"50839a4bb47ff4a0d6554fca251b4146"}}]}
{"data":{"cargos":{"totalCount":3,"edges":[{"node":{"trackingId":"VWX901"}},{"node":{"trackingId":"DEF456"}},{"node":{"trackingId":"ABC123"}}]}}}
{"data":{"cargo":null}}
```

The public instance refuses introspection, and the internal one answers:

```bash
curl -s --cacert $CA https://localhost:8371/graphql -H 'Content-Type: application/json' -H "Authorization: Bearer $OPS" \
  -d '{"query":"{ __schema { queryType { name } } }"}'
curl -s http://localhost:8373/graphql -H 'Content-Type: application/json' -d '{"query":"{ __schema { queryType { name } } }"}'
```

```json
{"data":null,"errors":[{"message":"GraphQL introspection has been disabled, but the requested query contained the field '__schema'.","locations":[{"line":1,"column":3}]},{"message":"GraphQL introspection has been disabled, but the requested query contained the field 'queryType'.","locations":[{"line":1,"column":14}]}]}
{"data":{"__schema":{"queryType":{"name":"Query"}}}}
```

Start a subscription as `ana` in one terminal, with the client on the backend network:

```bash
docker compose -f examples/27-final-project/compose.yaml run --rm -e TOKEN="$ANA" client \
  --url wss://edge:8444/graphql --tracking-id ABC123 --count 1 --frames
```

Register `REG_F1` as the operator in another, and read the plain feed as `ana`:

```bash
curl -s --cacert $CA https://localhost:8371/graphql -H 'Content-Type: application/json' -H "Authorization: Bearer $OPS" \
  -d '{"query":"mutation($i: RegisterHandlingEventInput!) { registerHandlingEvent(input: $i) { handlingEvent { id } userErrors { code } } }","variables":{"i":{"trackingId":"ABC123","type":"UNLOAD","location":"DEHAM","voyageNumber":"V100S","completionTime":"2026-10-09T15:00:00Z","idempotencyKey":"ch27-final-unload-1"}}}'
curl -s -m 3 --cacert $CA -H "Authorization: Bearer $ANA" -H 'Last-Event-ID: evt_9' https://localhost:8371/events/cargos/ABC123
```

```text
{"data":{"registerHandlingEvent":{"handlingEvent":{"id":"evt_10"},"userErrors":[]}}}
<<< {"id":"1","type":"next","payload":{"data":{"cargoHandled":{"id":"evt_10","type":"UNLOAD","location":{"name":"Hamburg"},"cargo":{"trackingId":"ABC123","delivery":{"transportStatus":"IN_PORT"}}}}}}
event: handled
data: {"id":"evt_10","trackingId":"ABC123","type":"UNLOAD","location":"DEHAM","completionTime":"2026-10-09T15:00:00Z"}
id: evt_10
```

`bo` subscribing to the same cargo gets one error message and no event: `{"error": [{"message": "not permitted to watch this cargo", ... "extensions": {"code": "FORBIDDEN"}}]}`. The two k6 runs are one command each:

```bash
docker compose -f examples/27-final-project/compose.yaml run --rm \
  -e RUN=cost -e TARGET=https://edge:8443/graphql -e STACK=quarkus -e TOKEN="$OPS" load
```

The last line of its output is k6's summary object. For the `cost` run it holds `iterations.count` 80, `checks.rate` 1 and `http_req_failed.rate` 0. `bash examples/27-final-project/verify.sh` runs all of it on both stacks, ends with the two loads and prints `PASS`.

## Decision

<div class="callout callout--safe"><p class="callout__title">Decision</p><p>The final project is where four axes of Chapter 2 are settled at once. <em>Aggregation across sources</em> is the batched calls under authorization, the same keys per request whatever the load. <em>Client diversity and shape variance</em> is one edge that carries queries, a WebSocket and an event feed, and a client that chooses the transport its environment allows. <em>Contract and evolution style</em> is the complete schema, proven equal to the canonical SDL on both stacks, with introspection kept for the instances that need it. <em>Operational and security cost</em> is paid in layers: the edge refuses what is cheap to refuse, the document limits refuse what is expensive, and identity decides the rest, once for the subscription and again for every field of every event. The tracking view therefore ships as one set of images with one environment contract, run by the same script in compose, by a chart on a cluster and by a wrapper on OpenShift Local, with each tier changing only values.</p></div>

## Where this goes next

This chapter assembled the earlier chapters into one system: the complete schema with subscriptions over WebSocket and SSE, Chapter 14's limits, Chapter 18's authorization on queries, subscriptions and the event feed, Chapter 17's introspection control, Chapter 19's telemetry, Chapter 25's edge and a two-run k6 load, with `assert_sdl_equals` as the last word on the contract.

Appendix A runs the chart for this chapter on OpenShift Local through a wrapper chart that adds only the objects OpenShift needs. The bibliography lists the specifications and books behind the book as a whole. For this chapter, read the GraphQL specification's "Subscription" and "Validation" sections, the `graphql-transport-ws` protocol document, the GraphQL-over-HTTP draft for status codes, and Keycloak's "Server administration" guide and its page on importing a realm. On the framework side read the Quarkus guides "OpenID Connect (OIDC) Bearer token authentication" and "SmallRye GraphQL", Strawberry's pages "Subscriptions" and "Authentication", and k6's "Thresholds". *Full Stack GraphQL Applications* covers authorization and authentication in "Adding authorization and authentication" and further production concerns in "Advanced GraphQL considerations".

## For deeper coverage

- William Lyon, *Full Stack GraphQL Applications* (Manning, 2022) — "Adding authorization and authentication" and "Advanced GraphQL considerations", which this chapter's token and introspection wiring builds on.
- *Cloud Native Design Patterns*, "Anti-Patterns" — the coupling-focused review heuristics worth running against a system assembled from six chapters at once.
- [Keycloak — Server Administration Guide](https://www.keycloak.org/docs/latest/server_admin/)
- [GraphQL over HTTP](https://graphql.github.io/graphql-over-http/draft/) — the status codes and media types behind every request this chapter defends.
- [Grafana k6 — Thresholds](https://k6.io/docs/using-k6/thresholds/) — the pass/fail rules the two load runs use.
