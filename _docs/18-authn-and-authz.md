---
title: "AuthN and AuthZ"
order: 18
part: "Security"
description: "Keycloak-issued JWTs validated on both stacks, identity without the token in the context, operation rules, ownership enforced at one choke point, a field rule that fails with a code, and 401 for tokens that do not validate."
duration: "13 min read"
---

## Learning objectives

By the end of this chapter you can:

- Validate a Keycloak-issued JWT for signature, issuer, audience and expiry on both stacks (`quarkus-oidc` configuration versus PyJWT's `PyJWKClient`), and return `401` for anything that fails.
- Keep only the identity, never the token, in the request context, and thread it correctly through batch resolvers that resume on another thread.
- Apply operation-, object- and field-level authorization rules, and explain why a refused object returns `null` while a refused field returns a coded `FORBIDDEN`/`UNAUTHENTICATED` error.
- Enforce ownership at one choke point (the booking source) so every path to a `Cargo` (`cargo`, `cargos`, `node`, `nodes`, `HandlingEvent.cargo`) obeys the same rule.
- State why a response that depends on the caller's identity must skip shared caches or carry the caller in its key.

## Why this matters

Authentication answers who the caller is; authorization answers what that caller may do. The two fail differently and the API keeps the difference: a caller nobody can identify is told to authenticate, and a caller who is known but not allowed is told no.

Keycloak issues the tokens, each stack validates them, and three rules apply to what a valid caller may see: one per operation, one per object and one per field. The owner of each booking is private data of the booking service and is not a field of any type, so no `viewer` field or `Cargo.shipper` appears in the SDL. Rules of this kind live outside the contract.

Three people use the API. `ana` ships for ACME and owns `VWX901`, `DEF456` and `ABC123`. `bo` ships for GLOBEX and owns `XYZ789`, `STU678` and `GHI345`. `ops` is port staff with the `operator` role and sees everything.

One query shows why a per-route rule is not enough:

```graphql
{ location(unLocode: "NLRTM") { name }
  cargo(trackingId: "ABC123") { trackingId handlingHistory(first: 2) { edges { node { id registrationTime } } } } }
```

The location is public reference data. The cargo belongs to ACME. The events within it belong to ACME too, but the time they were registered is for staff. A rule attached to the URL cannot express that, so the rules attach to operations, objects and fields.

## Tokens from an identity provider

The server does not keep passwords. A separate identity provider authenticates people and hands them a token, and the server only validates it. The realm `shipping` is imported from a committed file, `keycloak/shipping-realm.json`, and has the three users, two realm roles (`shipper` and `operator`) and three clients:

- `tracking-cli`, a public client. An audience mapper adds `tracking-api` to `aud`, and a second mapper copies the user's `shipper` attribute into a `shipper` claim.
- `other-cli`, the same without the audience mapper, so its tokens are valid but meant for something else.
- `short-cli`, which issues four-second tokens so a token can be watched expiring.

The access token is a JWT (RFC 7519): a header, a payload of claims and a signature. The server relies on `iss` (who issued it), `aud` (who it is for), `exp` (when it ends), `sub` (the user), `realm_access.roles` and `shipper`. Keycloak signs with a private key and publishes the public keys as a JWKS, a JSON document of keys at a well-known URL.

{% include excalidraw.html file="18-token-flow" alt="A client box labelled ana sends a password grant to the Keycloak token endpoint, which issues an access token. The token box lists its claims: issuer localhost 8282 realm shipping, audience tracking-api, realm_access roles shipper, shipper ACME, subject and expiry. An arrow labelled Authorization Bearer leads from the token to a GraphQL server box that validates signature, issuer, audience and expiry. A dashed arrow from the server to a Keycloak JWKS box is labelled keys. A valid token leads to a box that says identity in the context, with roles and shipper and no token. A dashed arrow from the server leads to a black box, HTTP 401 with WWW-Authenticate Bearer, for an altered, wrong-audience or expired token." caption="Figure 18.1: From a login to an identity. The server validates the token before any GraphQL runs and keeps only the identity; a token that fails exits as HTTP 401." %}

The lab gets tokens with the password grant, a shortcut for scripts that RFC 9700 (OAuth 2.0 Security Best Current Practice) says MUST NOT be used. A production client uses the authorization code flow with PKCE, so the application never sees a password. The realm also sets `sslRequired` to none, acceptable on `localhost` and nowhere else, and every password in the repository ends in `-fixture-pw` for the same reason.

A token's `iss` is the address the client used to reach Keycloak, `http://localhost:8282/realms/shipping` in the lab. The apps run inside the compose network and read keys from `keycloak:8080`, a different address. Each stack therefore pins the issuer explicitly and fetches keys over the back channel with discovery switched off. A token fetched at any other address is rejected.

## Validating a token

Validation checks four things, and a server that skips one is open (RFC 8725, "JSON Web Token Best Current Practices"):

| Check | What it stops |
|---|---|
| Signature verifies against a key from the issuer's JWKS | anyone writing a token |
| `iss` is the expected issuer | tokens from another provider |
| `aud` contains this API's audience | a token issued for any other service in the realm |
| `exp` is in the future | replay of an old token |

Neither stack parses a token by hand. On Quarkus the `quarkus-oidc` extension does all four from configuration:

```properties
quarkus.oidc.application-type=service
quarkus.oidc.auth-server-url=http://keycloak:8080/realms/shipping
quarkus.oidc.discovery-enabled=false
quarkus.oidc.jwks-path=protocol/openid-connect/certs
quarkus.oidc.token.issuer=http://localhost:8282/realms/shipping
quarkus.oidc.token.audience=tracking-api
quarkus.oidc.roles.role-claim-path=realm_access/roles
```

Python uses PyJWT. `PyJWKClient` fetches and caches the key set and picks the key a token names, and `jwt.decode` verifies the rest. The `require` option makes a token without `exp`, `iss`, `aud` or `sub` invalid instead of valid by omission:

```python
        try:
            # PyJWKClient does blocking I/O on a cache miss: keep it off the event loop.
            key = await run_in_threadpool(self._jwks.get_signing_key_from_jwt, token)
            claims = jwt.decode(
                token,
                key,
                algorithms=["RS256"],
                audience=self._audience,
                issuer=self._issuer,
                options={"require": ["exp", "iss", "aud", "sub"]},
            )
        except jwt.PyJWKClientConnectionError as error:
            raise HTTPException(503, "identity provider unavailable") from error
        except jwt.PyJWTError as error:
            raise HTTPException(
                401, "invalid token", headers={"WWW-Authenticate": 'Bearer error="invalid_token"'}
            ) from error
        return Identity(
            subject=claims["sub"],
            roles=frozenset(claims.get("realm_access", {}).get("roles", [])),
            shipper=claims.get("shipper"),
        )
```

A token that does not validate is not a GraphQL error. The request is refused at the HTTP layer with `401` and a `WWW-Authenticate: Bearer` header (RFC 6750), and no GraphQL runs. That holds even for a public field. A request with no `Authorization` header is different: it is anonymous, not a failure, and public data still works. An altered signature, a payload rewritten to claim the operator role under the old signature, a token for the wrong audience, a malformed token and an expired one are all 401 on both stacks.

## Identity in the context, nothing else

The context carries the identity, not the token. A resolver needs to know who is asking and which roles they hold, and a token in the context ends up in a log or a trace sooner or later.

On Quarkus the identity is the `SecurityIdentity`, which `quarkus-oidc` fills from the validated token. A small bean turns it into the `Viewer` the booking source needs:

```java
    public Viewer current() {
        if (identity.isAnonymous()) {
            return Viewer.ANONYMOUS;
        }
        String shipper = identity.getPrincipal() instanceof JsonWebToken token ? token.getClaim("shipper") : null;
        return new Viewer(identity.hasRole("operator"), shipper);
    }
```

Every resolver calls `viewers.current()` on entry and passes the result on. That matters because continuations resume on another thread after a source's delay, as the batch resolvers for `CargoEdge.node` and `HandlingEvent.cargo` do. Twelve concurrent requests from two callers each get only their own cargos.

On Python the identity is built once, in the dependency that builds the context, and `TrackingContext.identity` is the only authentication state: an `Identity` with the subject, a frozen set of roles and the shipper, or `None` for an anonymous caller. A bad token raises there, so the 401 happens before the GraphQL router sees the request.

## Operation-level rules

The coarsest rule is whether an operation may be called at all. `cargo` and `cargos` need a signed-in caller, and `registerHandlingEvent` needs the `operator` role. `location`, `voyage`, `node` and `nodes` stay open: they return public reference data, or null for what the caller may not see.

{% include codetabs.html langs="Quarkus|Python" %}

```java
    @Query
    @Authenticated
    @Description("Look up one cargo by its tracking id. Null when no such cargo exists.")
    public Uni<Cargo> cargo(
            @Name("trackingId") @NonNull @Description("The tracking id issued at booking.") TrackingId trackingId,
            Context context) {
        return booking.getCargo(context.getExecutionId(), trackingId.value(), viewers.current());
    }
```

```python
class IsAuthenticated(BasePermission):
    def has_permission(self, source: Any, info: Info[TrackingContext], **kwargs: Any) -> bool:
        return info.context.identity is not None

    def on_unauthorized(self) -> None:
        raise Unauthenticated("authentication required")
```

The Quarkus annotation is a standard security annotation. An interceptor runs the check before the method body, so a refused call reaches no source, and SmallRye reports the failure as an execution error at the operation's path. `@RolesAllowed("operator")` on the mutation works the same way. On Strawberry a field lists permission classes, and `permission_classes=[IsAuthenticated, IsOperator]` evaluates them in order.

Both stacks answer an anonymous `cargo(...)` the same way: `data.cargo` is null, and one error at `["cargo"]` carries the code `UNAUTHENTICATED` and the message `authentication required`. `cargos` is non-null, so the null climbs to `data`. A signed-in shipper who writes gets `FORBIDDEN` with `operator role required`, and because the mutation's payload is non-null, `data` is null too.

{% include excalidraw.html file="18-authorization-layers" alt="Three columns. The Operation column shows annotations and permission classes on cargo, cargos and registerHandlingEvent, then a refusal that is an error with the code UNAUTHENTICATED or FORBIDDEN, then a box saying no source is called. The Object column shows the paths that reach a cargo, all feeding one dark box, BookingSource, the one place the owner is checked, then a refusal that is a null with no error, the same answer as an unknown id. The Field column shows HandlingEvent.registrationTime for operators only, then a refusal that is FORBIDDEN at the field's path, then the null climbing to the nearest nullable parent, the edge's node." caption="Figure 18.2: Three layers of authorization. An operation or a field refuses with a coded error; an object refuses with a null." %}

Quarkus's security interceptor throws `UnauthorizedException` and `ForbiddenException`. `SecurityErrorTranslator`, a small interceptor outside Quarkus's own, swaps them for `AuthenticationRequiredException` and `OperatorRoleRequiredException`, which are `@ErrorCode` exceptions in the same allowlist as the outage error, so they pass the mask with the contract's messages. The check itself is still the framework's. On Python the permission classes raise `ExposedError` subclasses for the same reason: Strawberry's default permission error would be masked as `Internal server error.`, because the masking predicate trusts only exposed errors.

## Object-level rules: a shipper sees its own cargos

`cargos` is open to every signed-in caller, so something must keep ana from reading bo's cargos, and it must hold on every path to a cargo: `cargo`, `cargos`, `node`, `nodes`, the `node` of each edge and `HandlingEvent.cargo`. A check in each resolver is a check somebody forgets in the next one.

The rule lives in one place, the booking source, and every path to a cargo reads it. On Quarkus the source takes the `Viewer`:

```java
    private Cargo load(String trackingId, Viewer viewer) {
        // The rule runs before the load: a cargo the viewer may not see is not
        // loaded, so its outage (GHI345) cannot reveal that it exists.
        if (!viewer.canSee(data.owner(trackingId))) {
            return null;
        }
        if (UNAVAILABLE_CARGO.equals(trackingId)) {
            throw new SourceUnavailableException("booking service unavailable");
        }
        return data.cargo(trackingId);
    }
```

On Python the source is bound to the caller's identity when the context is built:

```python
    def _load(self, tracking_id: str) -> Cargo | None:
        # The rule runs before the load: a cargo the caller may not see is not
        # loaded, so its outage (GHI345) cannot leak its existence.
        if not visible(self.identity, data.OWNERS.get(tracking_id)):
            return None
        if tracking_id == "GHI345":
            raise SourceUnavailable("booking service unavailable")
        return data.CARGOS.get(tracking_id)
```

The listing applies the same rule earlier. `listCargos` filters the booking index by owner before it pages, so the page, the cursors, `hasNextPage` and `totalCount` all describe the caller's view. ana's `totalCount` is 3, not 6, and `cargos(routingStatus: NOT_ROUTED)` is empty for her because both unrouted cargos are GLOBEX's. A rule applied after paging would leak through the count, and one applied only to the nodes would show a page of nulls.

A cargo the caller may not see is `null` with no error, the same answer the server gives for an id that does not exist: `cargo(XYZ789)` and `cargo(ZZZ999)` return identical bodies for ana. An error such as "not yours" would tell her that `XYZ789` exists and belongs to someone else, and she could enumerate every tracking id that way.

`node` and `nodes` reach the same source. `nodes(ids: ["cargo_ABC123", "cargo_XYZ789", "evt_1", "evt_3"])` as bo returns `[null, Cargo XYZ789, null, null]`: ABC123 and its events are ACME's, so those positions are null and the order is kept. An event is as visible as its cargo, so `node(id: "evt_1")` returns the event for ana and null for bo. Anonymous callers get null for every cargo and event, and public locations and voyages still resolve.

The rule runs before the load, so a cargo the caller may not see is never loaded and its outage cannot reveal that it exists. bo owns `GHI345`, whose booking load fails, so bo's page of three reports `SERVICE_UNAVAILABLE`: Strawberry nulls one edge, and SmallRye fails the whole batch and nulls all three. ana's answer carries no trace of the outage.

## Field-level rules: errors or nulls

`HandlingEvent.registrationTime` is when the event entered the system, and only operators read it. A shipper may read the event, its type and its completion time, but not that field. The rule is stated where the field is declared. On Quarkus the field is a method with an annotation, and the record component is ignored:

{% include codetabs.html langs="Quarkus|Python" %}

```java
    @RolesAllowed("operator")
    @NonNull
    @Description("When the event was registered in the system.")
    public Instant registrationTime(@Source HandlingEvent event) {
        return event.registrationTime();
    }
```

```python
    @strawberry.field(
        description="When the event was registered in the system.",
        permission_classes=[IsAuthenticated, IsOperator],
    )
    def registration_time(self) -> datetime:
        return self.registered_at
```

A refused field is an error with a code at the field's own path, and the null lands where null propagation puts it. `registrationTime` is `DateTime!`, so the null climbs one step to the nearest nullable parent, the edge's `node`. When ana asks for the history of `ABC123` with `registrationTime`, both stacks return two errors, at `["cargo","handlingHistory","edges",0,"node","registrationTime"]` and the same path with `1`. Both nodes are null and both cursors survive, so a client can still paginate. Through `node(id: "evt_1")` the nearest nullable parent is `node` itself, and `data.node` is null. Without the field, ana gets her events with no error.

{% include excalidraw.html file="18-errors-vs-nulls" alt="Two panels. The left panel, a refused field, shows ana asking for handlingHistory first 2 with node id and registrationTime on cargo ABC123. Two amber boxes show edges 0 and 1 with node null and the cursor surviving. A dark box says two errors with code FORBIDDEN and the message operator role required at the registrationTime paths. A last box explains that DateTime non-null cannot be null, so the null climbs one step to the nullable node and the page and cargo survive. The right panel, a refused object, shows cargo XYZ789 asked by ana, an amber box saying data.cargo is null with no errors, and a box saying cargo ZZZ999 gives the identical body so the caller cannot enumerate other shippers." caption="Figure 18.3: Fields: error. Objects: null. A refused field says so at its path, and a refused object looks like one that does not exist." %}

The two answers differ by design. An object that is not yours is better as a plain null, because an error would confirm it exists. A field is the opposite: it is in the schema and any client can see it, so there is nothing to hide, and a null would be ambiguous. A client that gets null for `registrationTime` cannot tell "not allowed" from "no value". An error with `FORBIDDEN` at the path gives it something to act on. A nullable field could return null instead, and Strawberry has a permission mode for that; it is not used here, because a null on a refused field turns an access decision into data that looks like a fact about the cargo.

### Writes need a role

`registerHandlingEvent` is the operator's, by the same operation rule. ana gets `FORBIDDEN` at `["registerHandlingEvent"]`, an anonymous caller gets `UNAUTHENTICATED`, and neither writes anything. ops registers the unload of `ABC123` as `evt_10`, and the payload's `registrationTime` is readable because ops is an operator. The check runs before the idempotency check, so a refused caller cannot learn whether a key was used.

## Codes the client can act on

Two codes join `SERVICE_UNAVAILABLE` and `BAD_USER_INPUT`, with fixed messages identical on both stacks:

| Code | Raised for | Message | Client action |
|---|---|---|---|
| `UNAUTHENTICATED` | an anonymous caller reaching an operation that needs a signed-in one | `authentication required` | log in, or refresh the token |
| `FORBIDDEN` | a signed-in caller without the operator role | `operator role required` | a login will not help |

Both pass through the allowlist of exposed errors, and everything else is still masked: no `io.quarkus` class name and no exception name reaches a client.

The HTTP 401 for a bad token is outside this vocabulary. It is not an error in a GraphQL response, because no GraphQL ran. A client library should treat it as an authentication problem for the whole request, usually by fetching a fresh token and retrying once. The GraphQL-over-HTTP specification expects this: a request the client may not make gets 401 or 403 (its "Status Codes" section), and decisions about the data are made during execution.

## Caching and identity

A response that depends on the caller must not be reused for another one. Skip shared caches when an `Authorization` header is present, and put the caller in the key of anything cached inside the server whose value depends on the caller. The booking source applies the ownership rule before anything below it is read, so a cached event list is reached only through a cargo the caller may see. Reference data nobody owns, locations and voyages, is the only data where a shared cache is safe. The same care applies to telemetry: a trace attribute for the subject is fine, and a token or an owner list is not.

> **Decision**
>
> One query reads reference data nobody owns and cargo somebody does, so rules attach to operations, objects and fields, not routes. A refused object is a null, so a client cannot enumerate other shippers; a refused field is a coded error, so a client can tell it from an absent value. Validate a signed token before any GraphQL runs, keep the identity and not the token in the context, state each rule in one place, return `UNAUTHENTICATED` and `FORBIDDEN` as stable codes, and answer HTTP 401 for a token that does not validate.

> **🤖 Explore with your agent**
>
> "In examples/18-authn-authz, add a field rule: make `HandlingEvent.location` readable only by the operator role, using `@RolesAllowed` on the Quarkus resolver and `permission_classes=[IsAuthenticated, IsOperator]` on the Strawberry field. Follow the rule that a refused field is a coded FORBIDDEN error at its path and a refused object is a null, and say which nullable parent the null climbs to."
>
> Check: run `bash examples/18-authn-authz/verify.sh` to confirm the existing rules still hold, then ask as ana for `handlingHistory { edges { node { location { name } } } }` and expect FORBIDDEN errors at the `location` paths.

## Build, run, observe

`bash examples/18-authn-authz/verify.sh` runs the whole sequence on both stacks and prints `PASS` only when both hold. To explore by hand, start the stack. Quarkus is on `8280`, Python on `8281` and Keycloak on `8282`. Tokens come from `localhost:8282`, the address the apps pin as the issuer.

```bash
docker compose -f examples/18-authn-authz/compose.yaml up -d --build
tok() {
  curl -s localhost:8282/realms/shipping/protocol/openid-connect/token \
    -d grant_type=password -d client_id=tracking-cli -d username=$1 -d password=$1-fixture-pw \
    | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["access_token"])'
}
Q() {  # Q <port> <token or ""> <query>
  curl -s localhost:$1/graphql -H 'Content-Type: application/json' ${2:+-H "Authorization: Bearer $2"} \
    -d "$(python3 -I -c 'import json,sys; print(json.dumps({"query": sys.argv[1]}))' "$3")"; echo
}
ANA=$(tok ana); BO=$(tok bo); OPS=$(tok ops)
```

An anonymous caller reaches the public location and is refused the cargo. Python:

```bash
Q 8281 "" '{ location(unLocode: "NLRTM") { name } }'
Q 8281 "" '{ cargo(trackingId: "ABC123") { trackingId } }'
```

```json
{"data":{"location":{"name":"Rotterdam"}}}
{"data":{"cargo":null},"errors":[{"message":"authentication required","locations":[{"line":1,"column":3}],"path":["cargo"],"extensions":{"code":"UNAUTHENTICATED"}}]}
```

ana sees her three cargos and a count of three; bo asks for two and gets two of GLOBEX's. Quarkus:

```bash
Q 8280 $ANA '{ cargos(first: 10) { totalCount edges { node { trackingId } } } }'
Q 8280 $BO '{ cargos(first: 2) { totalCount edges { node { trackingId } } } }'
```

```json
{"data":{"cargos":{"totalCount":3,"edges":[{"node":{"trackingId":"VWX901"}},{"node":{"trackingId":"DEF456"}},{"node":{"trackingId":"ABC123"}}]}}}
{"data":{"cargos":{"totalCount":3,"edges":[{"node":{"trackingId":"XYZ789"}},{"node":{"trackingId":"STU678"}}]}}}
```

ana asking for `registrationTime` gets an error with a path and a null node. Python:

```bash
Q 8281 $ANA '{ node(id: "evt_1") { id ... on HandlingEvent { registrationTime } } }'
```

```json
{"data":{"node":null},"errors":[{"message":"operator role required","locations":[{"line":1,"column":46}],"path":["node","registrationTime"],"extensions":{"code":"FORBIDDEN"}}]}
```

A token that does not validate:

```bash
BAD="${ANA%.*}.AAAA"
curl -si localhost:8280/graphql -H "Authorization: Bearer $BAD" -H 'Content-Type: application/json' -d '{"query":"{ __typename }"}' | head -3
```

```text
HTTP/1.1 401 Unauthorized
www-authenticate: Bearer
```

Python's header is `Bearer error="invalid_token"` with the body `{"detail":"invalid token"}`. Codes, paths, messages and counts match across stacks except where the table says so.

| Check | Quarkus | Python |
|---|---|---|
| anonymous `location(NLRTM)` | `Rotterdam`, no errors | the same |
| anonymous `cargo(ABC123)` | null; error at `["cargo"]`, `UNAUTHENTICATED`, `authentication required`; 0 source calls | the same |
| anonymous `cargos(first: 2)` | `data` null, `UNAUTHENTICATED` | the same |
| anonymous `nodes(["loc_NLRTM","cargo_ABC123"])` | `[Location, null]`, no errors | the same |
| ana, `cargos(first: 10)` | `VWX901`, `DEF456`, `ABC123`; `totalCount` 3 | the same |
| ana, `cargos(routingStatus: NOT_ROUTED)` | `totalCount` 0 | the same |
| ana, `cargo(XYZ789)` and `cargo(ZZZ999)` | null, no errors, identical bodies | the same |
| ana, `node(cargo_XYZ789)` and `node(evt_1)` | null; the event resolves | the same |
| ana, `node(evt_1) { ... on HandlingEvent { cargo { trackingId } } }` | `ABC123`, no errors | the same |
| bo, `cargos(first: 2)` | `XYZ789`, `STU678`; `totalCount` 3 | the same |
| bo, `cargos(first: 10)` | 3 errors, all three nodes null | 1 error at edge 2; nodes `XYZ789`, `STU678`, null |
| bo, `cargo(ABC123)`, `node(cargo_ABC123)`, `node(evt_1)` | null, no errors | the same |
| bo, `nodes(cargo_ABC123, cargo_XYZ789, evt_1, evt_3)` | `[null, XYZ789, null, null]` | the same |
| ops, `cargos(first: 10) { totalCount }` | 6 | the same |
| ana, `registrationTime` on ABC123's history | 2 `FORBIDDEN` errors at the field paths; both nodes null; both cursors present | the same |
| ana, `node(evt_1)` with `registrationTime` | `data.node` null; error at `["node","registrationTime"]` | the same |
| ops, `registrationTime` | `2026-10-01T08:35:00Z`, `2026-09-30T16:05:00Z` | the same |
| ana and anonymous writes | `data` null; `FORBIDDEN` / `UNAUTHENTICATED`; 0 calls | the same |
| ops write | `evt_10`, `IN_PORT`, one `appendEvent` | the same |
| altered signature, altered payload, wrong audience, malformed, expired | 401, `WWW-Authenticate: Bearer`, no GraphQL body | 401, `Bearer error="invalid_token"`, `{"detail":"invalid token"}` |
| twelve concurrent requests, two callers | each caller gets only its own cargos | the same |
| schema | anonymous introspection conforms; `finalArrivalDate` deprecated; only `Subscription` unserved | the same |

Stop the stack when done:

```bash
docker compose -f examples/18-authn-authz/compose.yaml down -v
```

- Fetch the token from `other-cli`, which has no audience mapper: it is valid but meant for something else, and both stacks answer 401.
- Fetch a token from `short-cli` and wait four seconds: the same token that worked now answers 401.

## For deeper coverage

- William Lyon, *Full Stack GraphQL Applications* (Manning, 2022), chapter "Adding authorization and authentication": the `@auth`-directive placement, where rules are written in the schema, in contrast with keeping them outside the SDL.
- Cloud Native Design Patterns, chapter "Security": the identity and access-control patterns that the three authorization layers apply to GraphQL.
- RFC 6750 (bearer tokens), RFC 7519 (JWT), RFC 8725 (JWT best practices), RFC 9700 (OAuth 2.0 security) and OpenID Connect Core for the difference between an ID token and an access token.
- [OWASP GraphQL Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/GraphQL_Cheat_Sheet.html), "Access Control" section.
- Keycloak Server Administration and Server guides: importing realms, hostname, health.
- Quarkus [OIDC bearer token authentication guide](https://quarkus.io/guides/security-oidc-bearer-token-authentication) and the security section of the [SmallRye GraphQL guide](https://quarkus.io/guides/smallrye-graphql).
- Strawberry [permissions guide](https://strawberry.rocks/docs/guides/permissions) and the PyJWT documentation for `PyJWKClient`.
