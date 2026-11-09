---
title: "The final project"
order: 27
part: "Running It & the Final Project"
description: "The whole tracking view as one system: the complete schema with subscriptions over WebSocket and SSE, query limits, Keycloak tokens with operation, object and field authorization, introspection on internal instances only, one edge, and the same images in every tier."
duration: "12 min read"
---

## Learning objectives

By the end of this chapter you can:

- Order a request's defences so the cheapest refusal (TLS, body size, cost budget) runs before an expensive one, like an authorization lookup.
- Wire Keycloak bearer tokens through operation, object, and field authorization on queries, subscriptions, and a plain `/events/` feed.
- Serve one image as a public instance with introspection off and an internal instance with it on, selected by an environment key.
- Keep a subscription's one-time admission check (`IsAuthenticated`, `CanWatchCargo`) separate from its per-event field check (`registrationTime`).
- Run the same two images unchanged across a Compose tier, a Helm chart on minikube, and an OpenShift Local wrapper chart, changing only configuration values.

## Why this matters

Each technique works alone. A system needs them together: the complete schema, `Subscription` included, requests that carry tokens so that what a caller may see depends on who it is, a document that costs too much refused before a source is asked, and introspection answering on the instances developers use and not on the ones clients reach. The work is in the seams, where one technique has to know about another.

The final project starts from the Compose edge-and-tier example and ports in subscriptions, depth and cost limits, token auth and field authorization, and introspection control, with `verify.sh` run after each port. Each ported file keeps a header comment naming where it came from. The canonical SDL does not change, and the last check proves it: both stacks serve exactly the schema in `contracts/schema/`.

## The system

The public instances of Quarkus and Python are the ones a client reaches, through the edge, and they publish nothing. Each stack also runs a second time from the same image as an internal instance, with introspection on, published on `127.0.0.1` only. Keycloak issues the tokens. The Grafana LGTM image receives the telemetry. Two more services sit behind Compose profiles and start only when a script runs them: a subscription client and the k6 runner.

{% include excalidraw.html file="27-final-architecture" alt="A band for the compose project holds a client on the left that sends a bearer token and a traceparent over TLS 1.3 to the edge, labelled the Compose edge, which proxies slash graphql, the WebSocket upgrade and slash events to the public instances of Quarkus and Python, labelled depth and cost limits, transport security, auth, and subscriptions, with introspection off and no published port. A dashed arrow joins the public instances to the internal instances, which run the same images with introspection on and publish on 127.0.0.1 ports 8372 and 8373. Amber arrows run from the public instances to Keycloak 26.8.1, labelled the identity provider, and from the application instances to lgtm 0.37.0, labelled observability and the Compose tier. Below sit the client profile, labelled the subscription client, the load profile with k6 v2.3.0, labelled load testing, and the contracts schema directory that the internal instances are compared with. A dashed box lists the components that stay out." caption="Figure 27.1: The final project's compose tier. Public instances sit behind the edge with introspection off; internal instances run the same images with it on." %}

Four topics stay out. A persisted-query allowlist is a deployment decision, built from a client's documents at release time. Response caching does not combine with it: a response that depends on the caller's token is private, so a shared cache must not hold it, and per-shipper answers would only ever miss. Federation describes a different topology, many services behind a gateway. Client integration, contract and integration testing, and the dev-mode debugging instances serve people who change the code. The load run reuses the k6 runner and its two documents instead, and a seeded fault has no place in a system meant to be correct.

## A request's defences, in order

A request meets a fixed sequence of decisions, and each has its own answer when it refuses.

{% include excalidraw.html file="27-request-defences" alt="Three horizontal bands show the order of the defences. The first band, before GraphQL runs, holds the TLS 1.3 listener, the 64k body limit and token validation, with a dashed arrow labelled refused to a dark box listing a failed TLS 1.2 handshake, a 413 status, and a 401 status with a WWW-Authenticate Bearer challenge. The second band, before any resolver runs, holds the token limit of 5000, the depth and alias rules and the cost budget of 1000, with a dashed arrow labelled refused to a dark box stating a 200 response with no data, the message maximum query complexity exceeded 7651 over 1000, and zero source calls. The third band, while the operation runs, holds the operation rule, which answers UNAUTHENTICATED at the root field, the object rule, under which a cargo of another shipper is null, the field rule, which answers FORBIDDEN at registrationTime, the batched sources with eight calls on Quarkus and six on Python, and error masking with extensions.traceId. Amber arrows join the bands." caption="Figure 27.2: The defences in the order a request meets them, and the answer each gives. The values are the ones both stacks return." %}

The first three are the edge's and the identity layer's. A TLS 1.2 client cannot finish the handshake. A body over 64k gets `413` from nginx, and the backend's source-call log stays empty because the request never arrived. A token for another audience gets `401` with a `WWW-Authenticate` challenge, before any GraphQL runs. Quarkus answers with `Bearer` and an empty body, Python with `Bearer error="invalid_token"` and a small JSON body.

The next three belong to the document and run before any authorization rule. The depth and cost limits read the document and the variables, never the caller, so an anonymous request with a document priced at 7,651 against a budget of 1,000 is refused the same way an operator's would be: status `200`, no `data`, one error that states the price, and no source call. The depth and alias limits read the same way. The two stacks count depth differently, one counting a root field as 1 and the other as 0, so their limits are 15 and 14 and the messages differ; both refuse the same documents.

The last group runs inside the operation:

- An anonymous caller reaching `cargo` gets `UNAUTHENTICATED` at the root field's path.
- A shipper asking for a cargo that another shipper owns gets `null` and no error, the same answer as for an unknown id, so the response does not reveal which tracking ids exist.
- A shipper asking for `registrationTime` gets `FORBIDDEN` at that field's path and a null edge node, while the rest of the page survives.
- What remains goes to the sources in batched calls: eight on Quarkus, six on Python, with the same keys.
- A failure that is not an exposed error is masked, and every error that reaches a client carries the trace id that finds it in Tempo and Loki.

The order matters. The cost check runs before the authorization rules, so a refusal for cost needs no knowledge of the caller. Reversed, every over-budget request would first cost an ownership lookup in the booking source. The edge's checks come first for the same reason: the cheapest refusal is the one made before the application is involved.

## Identity on every path

The edge passes `Authorization` through unchanged. Validation stays in the stacks. Quarkus validates with `quarkus-oidc` in service mode. Python validates with PyJWT and a `PyJWKClient` that fetches Keycloak's keys. Both read the keys over the backend network, from `keycloak:8080`, and both compare the token's issuer with a pinned value.

The two addresses differ because they do different jobs. A token carries the address its client fetched it from, `http://localhost:8374/realms/shipping`, because that is where Keycloak is published. The stacks can't reach that address from inside the network. The back channel is the service name; the issuer is a string to compare. Both are configuration, which is what lets one image run in three tiers:

{% include codetabs.html langs="Quarkus|Python" %}

```properties
QUARKUS_OIDC_AUTH_SERVER_URL=http://keycloak:8080/realms/shipping
QUARKUS_OIDC_TOKEN_ISSUER=http://localhost:8374/realms/shipping
```

```properties
TRACKING_OIDC_JWKS_URL=http://keycloak:8080/realms/shipping/protocol/openid-connect/certs
TRACKING_OIDC_ISSUER=http://localhost:8374/realms/shipping
```

A cluster changes the two values and nothing else, and so does an OpenShift Local project. The application has no code path that depends on the tier.

## Real time through the edge

A subscription arrives as a WebSocket upgrade, so the edge has two jobs it does not have for queries. It forwards the upgrade headers, using the `Upgrade` and `Connection` map the Compose edge configuration already carried unused, and it holds an idle connection open with a longer read timeout on the proxied locations, because a subscriber is silent between events. The event feed is a long response and needs its own location:

```nginx
        location = /graphql {
            proxy_pass $backend;
        }
        location /events/ {
            proxy_pass $backend;
            proxy_buffering off;
        }
```

`proxy_buffering off` lets each event reach the client as it is written, and `$backend` is the variable form of the upstream, which nginx resolves per request through Docker's DNS. In the cluster it resolves through the Service name.

The token travels on the upgrade request. Quarkus authenticates the upgrade like any HTTP request, and Python reads the `Authorization` header from the WebSocket connection in the same dependency that reads it from a `Request`. A token that does not validate refuses the upgrade, as it refuses a query. With no token the client connects as an anonymous caller, and the operation rule decides what happens next.

The operator `ops` sends `REG_F1`, an `UNLOAD` of `ABC123` at Hamburg, through the edge. The handling store records it as `evt_10` and broadcasts it, and each subscriber hears it under its own rights.

{% include excalidraw.html file="27-subscription-path" alt="Four clients on the left connect to the edge: ana subscribing over wss with a bearer token, bo doing the same, ana reading the plain event feed from the event id evt_9, and ops sending the mutation REG_F1. The edge, which keeps the Authorization header and the upgrade headers, leads to an admission box that checks once that the caller is signed in and may see ABC123, to a dark box where bo receives an error message with the code FORBIDDEN and no event follows, and to the feed box that answers 401, 403 or 200 and replays evt_10 after evt_9. The mutation reaches the handling store, which stores evt_10 and broadcasts it. Two amber boxes on the right show the next message to ana, a fresh execution with Hamburg, IN_PORT and registrationTime FORBIDDEN, and the next message to ops, the same selection with registrationTime as a value. Below them are the frames of ana's run and a TrackCargo query that then says IN_PORT." caption="Figure 27.3: One registration, heard by each subscriber under its own rights. Admission happens once, when the subscription starts; field authorization happens again on every event." %}

Two kinds of rule apply, at different times. The operation rule and the object rule are decided once, when the subscription starts: the caller must be signed in and allowed to see the cargo it names. On Python they are permission classes on the field, and `CanWatchCargo` reuses the ownership function from field authorization:

```python
    @strawberry.subscription(
        description="Emits each new handling event for one cargo as it is registered.",
        # Operation and object authorization, once, before the first event.
        # Field authorization (HandlingEvent.registrationTime) applies to every event.
        permission_classes=[IsAuthenticated, CanWatchCargo],
    )
```

On Quarkus the same two checks are `SubscriptionGate`, a graphql-java instrumentation installed in the chain that already carries the cost limit and the subscription layer's loader reset:

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

`SubscriptionGate` runs while the engine creates the event stream, so a refusal reaches the client as an error message with the code, `UNAUTHENTICATED` or `FORBIDDEN`, and no event follows. Both stacks refuse an unknown cargo and another shipper's cargo with the same message, because an error that differed would tell a caller which tracking ids exist.

The field rule can't be decided once. The selection set runs again for every event, and `registrationTime` is for operators. Python keeps the subscriber's identity in the connection's context, so the permission class on the field answers for the subscriber every time. On Quarkus, `SubscriberIdentity` takes the subscriber's `SecurityIdentity` when the subscription starts and delivers each event in a request context that holds it. `@RolesAllowed("operator")` and the `Viewers` class then answer for the subscriber, including in the continuations that resume after a source's latency. It is the same annotation used for field authorization on queries.

Where the refused field sits matters. `cargoHandled` and `registrationTime` are both non-null, so a refused field selected on the event itself would null the whole event under GraphQL's non-null propagation rule. Selected through `cargo.handlingHistory`, which sits under nullable parents, the null stops at the nullable edge node. For `ana` the event arrives with two `FORBIDDEN` errors at the field's path and both history nodes null. For `ops` the same document returns both values. One registration, three subscribers, three answers.

The plain feed applies the same rules before it starts streaming. `GET /events/cargos/ABC123` is `401` without a token and `403` for `bo`. For `ana`, a reconnect with `Last-Event-ID: evt_9` replays `evt_10`, then continues live. Python also serves GraphQL over SSE on the same path as the WebSocket, a fourth subscriber. The count of live subscribers, read inside the containers, returns to zero on both channels when the clients leave.

## The complete schema

`assert_sdl_equals` compares each internal instance with the canonical SDL in both directions. Nothing is missing and nothing is extra: the schema that two frameworks built from annotated and decorated code is the schema in `contracts/schema/`, `Subscription` and its description included. The check ignores the framework's own additions by name, and one deprecation, `Itinerary.finalArrivalDate`, which the canonical file declares as a directive and the live schema reports as state.

The public instances answer the same request with a refusal, even for an operator. Quarkus says `Introspection has been disabled for this request`. Python says introspection has been disabled and names the field. A schema that clients must not enumerate is still a schema the build must be able to read. One image with two kinds of instance serves both, selected by `TRACKING_INTROSPECTION_ENABLED` on Quarkus and `TRACKING_PUBLIC` on Python, so a third kind of instance needs no code.

## Observing it

A trace id sent in a `traceparent` header through the edge comes back as `extensions.traceId` on the error at the sixth edge of `cargos(first: 10)`, the booking outage of `GHI345`. Tempo holds the operation span under that id. The number of `source.call` spans for `getLocations` equals the number of such calls in the source-call log: one call for many locations shows as one span. Loki returns a record for the same `trace_id`. No span carries a credential. The token is validated before the operation span opens, and the span records the operation and the route, never the token or an argument value.

## Defending it under load

k6 runs on the backend network and reaches the edge by name, over TLS, with an operator's token. It trusts the lab's certificate authority through `SSL_CERT_FILE`, so the run exercises the same listener a client uses. Two runs bear on defence:

- `fanout`: 80 `FanOut` requests from eight virtual users.
- `cost`: 40 `FanOut` and 40 `OverBudget` requests at the same time.

The thresholds judge correctness: no transport failure, every check true, every scheduled request run. Latency appears in the summary and no assertion reads it. In `fanout` the source-call log holds 80 distinct request ids, each with one request's calls (eight on Quarkus, six on Python), so under eight concurrent virtual users no request's keys enter another's batch. In `cost` it holds 40 request ids, not 80, because a refused request makes no call: the over-budget document costs one token validation, one parse and one price calculation.

## Three tiers, one image

`verify.sh` is the Compose tier. A Helm chart runs the same three images, `gql-ch27-quarkus:1.0`, `gql-ch27-python:1.0` and `gql-ch27-client:1.0`, on the minikube profile, and a wrapper chart runs that chart on OpenShift Local. What changes between tiers is configuration: the issuer, the address of the identity provider, who terminates TLS, and how a client reaches the edge. The environment contract in the README lists what to set. A service that has to be patched per tier has hidden its differences in the code; this one keeps them in values a platform owner can read.

> **Decision**
>
> Ship the tracking view as one set of images with one environment contract, run by the same script in Compose, by a chart on a cluster and by a wrapper chart on OpenShift Local, each tier changing only values. Pay the security cost in layers: the edge refuses what is cheap to refuse, the document limits refuse what is expensive, and identity decides the rest, once for the subscription and again for every field of every event. Prove the contract by comparing the complete schema with the canonical SDL on both stacks, and keep introspection for the instances that need it.

## Build, run, observe

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

`bo` subscribing to the same cargo gets one error message and no event: `{"error": [{"message": "not permitted to watch this cargo", ... "extensions": {"code": "FORBIDDEN"}}]}`. Each k6 run is one command:

```bash
docker compose -f examples/27-final-project/compose.yaml run --rm \
  -e RUN=cost -e TARGET=https://edge:8443/graphql -e STACK=quarkus -e TOKEN="$OPS" load
```

The last line of its output is k6's summary object. For `cost` it holds `iterations.count` 80, `checks.rate` 1 and `http_req_failed.rate` 0. `bash examples/27-final-project/verify.sh` runs everything on both stacks, ends with the two loads and prints `PASS`.

Experiments:

- Send `bo`'s token for `ABC123`: `cargo` is `null` with no error, the same as an unknown id.
- Send the `OverBudget` document anonymously: status `200`, no `data`, the price in the message, and no source call.
- Subscribe as `ana` and register an event as `ops`: `registrationTime` is `FORBIDDEN` for `ana` and a value for `ops`.
- Send a 100 KB body: `413` at the edge, and the source-call log stays empty.

## For deeper coverage

- William Lyon, *Full Stack GraphQL Applications* (Manning, 2022): "Adding authorization and authentication" and "Advanced GraphQL considerations", which the token and introspection wiring builds on.
- *Cloud Native Design Patterns*, "Anti-Patterns": the coupling-focused review heuristics worth running against an assembled system.
- [Keycloak: Server Administration Guide](https://www.keycloak.org/docs/latest/server_admin/)
- [GraphQL over HTTP](https://graphql.github.io/graphql-over-http/draft/): the status codes and media types behind every request.
- [Grafana k6: Thresholds](https://k6.io/docs/using-k6/thresholds/): the pass/fail rules the two load runs use.
