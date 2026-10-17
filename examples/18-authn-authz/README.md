# Ch18 - AuthN and AuthZ

Keycloak issues the tokens. Each stack validates them (Quarkus with `quarkus-oidc`, Python with PyJWT and
`PyJWKClient`) and then authorizes three ways: per operation (`cargo`, `cargos` and
`registerHandlingEvent`), per object (a shipper sees only the cargos it owns, on every path to a cargo) and per
field (`HandlingEvent.registrationTime` is for operators). Refusals use two codes, `UNAUTHENTICATED` and
`FORBIDDEN`, and a token that does not validate is HTTP 401 before GraphQL runs. `verify.sh` asserts all of it on
both stacks.

This example does not repeat Chapter 14's limits or Chapter 17's transport controls; production would carry both.

## The served slice

`contracts/schema/shipping/*.graphql` is the canonical SDL. This chapter serves everything in it except
`Subscription`, which Chapter 21 builds. The schema is the one Chapter 13 serves: ownership, roles and tokens
live outside the SDL (Chapter 5), so no type, field or argument changes. `assert_sdl_conforms` reads the schema
as an anonymous caller: introspection is open in this chapter, and Chapter 17 closes it. Nothing in the schema
says which operations need a role (SmallRye adds `@rolesAllowed` directive definitions, which the harness
filters like its other framework directives).

### Users, clients and ownership

The realm is `examples/18-authn-authz/keycloak/shipping-realm.json`, imported by `start-dev --import-realm`.
**Every password, and the Keycloak admin login in `compose.yaml`, is a test fixture for this lab.**

| User | Password | Realm role | `shipper` claim | Sees |
|---|---|---|---|---|
| `ana` | `ana-fixture-pw` | `shipper` | `ACME` | VWX901, DEF456, ABC123 |
| `bo` | `bo-fixture-pw` | `shipper` | `GLOBEX` | XYZ789, STU678, GHI345 |
| `ops` | `ops-fixture-pw` | `operator` | none | every cargo, every field |

| Client | Purpose |
|---|---|
| `tracking-cli` | public client, password grant on (lab only), audience mapper adds `tracking-api`, mapper for the `shipper` claim |
| `other-cli` | the same without the audience mapper: its tokens are for another audience |
| `short-cli` | like `tracking-cli` with a four-second token lifetime, to show an expired token |

The owner of each booking is private data of the booking service (`TrackingData.owners`, `data.OWNERS`). It is
not a field of any type.

The password grant is here so a script can obtain a token with one request. RFC 9700 (OAuth 2.0 Security Best
Current Practice) says the grant MUST NOT be used: production clients use the authorization code flow with PKCE. The realm also sets
`sslRequired: none`, for the lab only.

## Run it

```bash
bash examples/18-authn-authz/verify.sh
```

`verify.sh` brings up Keycloak and both services with `docker compose`, waits for the realm, fetches a token
per user, runs the cases below in a fixed order on each stack, diffs each live schema against
`contracts/schema/` and tears everything down. It prints `PASS` only if every check holds on **both** stacks.
It needs Docker Engine with the `docker compose` plugin and Node/npm (for the pinned `graphql-inspector`).
Keycloak needs about 600 MB and 25 to 40 seconds to become healthy.

To explore by hand:

```bash
docker compose -f examples/18-authn-authz/compose.yaml up -d --build
TOKEN=$(curl -s localhost:8282/realms/shipping/protocol/openid-connect/token \
  -d grant_type=password -d client_id=tracking-cli -d username=ana -d password=ana-fixture-pw \
  | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')
curl -s localhost:8280/graphql -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" \
  -d '{"query":"{ cargos(first: 10) { totalCount edges { node { trackingId } } } }"}'
docker compose -f examples/18-authn-authz/compose.yaml down -v
```

Use port `8281` for the Python stack. **Fetch tokens at `localhost:8282`**: the token's `iss` claim is the
address the request used, and both stacks pin `http://localhost:8282/realms/shipping`. The apps read the signing
keys from `keycloak:8080` on the compose network (the back channel), so a token fetched at another address is
rejected with 401.

## The source-call log (lab only)

`GET /debug/source-calls` answers `200 {"calls":[...]}`, ordered by `startMs`; `DELETE` clears it and answers
`204`. Entries are as in Chapter 13. Only calls to the owners are logged. A refused operation never reaches a
source, so its log is empty; a cargo the caller may not see still appears as one `booking` call; the rule runs inside it and nothing is loaded. The endpoints answer only when `TRACKING_DEBUG_ENDPOINTS=true` (compose sets it).

## Ports

| Service | Container | Host | Endpoint |
|---|---|---|---|
| Quarkus | 8080 | 8280 | `/graphql` (health at `/q/health`) |
| Python | 8080 | 8281 | `/graphql` (health at `/health`) |
| Keycloak | 8080 | 8282 | `/realms/shipping` (management port 9000 is not published) |

Compose project `gql-ch18-authn-authz`, containers `ch18-authn-authz-*`. The apps start after
Keycloak's healthcheck passes. Telemetry is off by default. Add the observability file (`docker
compose -f compose.yaml -f compose.observability.yaml up --build`) to send it to LGTM, which
publishes the fixed host ports 3000, 4317, 4318, 9090, 3100 and 3200, so run one example's
observability stack at a time.

## On the wire

Each value below is asserted by `verify.sh`.

| Case | Request | Quarkus | Python |
|---|---|---|---|
| public data, anonymous | `location(unLocode: "NLRTM") { name }` | `Rotterdam`, no errors | the same |
| anonymous, authenticated operation | `cargo(trackingId: "ABC123")` | `data.cargo` null; one error at `["cargo"]`, code `UNAUTHENTICATED`, message `authentication required`; 0 source calls | the same |
| | `cargos(first: 2) { totalCount }` | `data` null; code `UNAUTHENTICATED` at `["cargos"]` | the same |
| anonymous `nodes` | `["loc_NLRTM", "cargo_ABC123"]` | `[Location, null]`, no errors | the same |
| ana, her cargos | `cargos(first: 10)` | `VWX901`, `DEF456`, `ABC123`; `totalCount` 3 | the same |
| ana, filter and ownership | `cargos(routingStatus: NOT_ROUTED)` | `totalCount` 0 (both are GLOBEX's) | the same |
| ana, another shipper's cargo | `cargo(XYZ789)`, `cargo(GHI345)` | null, no error; identical to `cargo(ZZZ999)` | the same |
| ana, nodes | `node(cargo_XYZ789)`, `node(evt_1)` | null; `evt_1` resolves (ABC123 is ACME's) | the same |
| ana, `HandlingEvent.cargo` | `node(id: "evt_1") { ... on HandlingEvent { cargo { trackingId } } }` | `ABC123`, no errors | the same |
| bo, first page | `cargos(first: 2)` | `XYZ789`, `STU678`; `totalCount` 3; `hasNextPage` true | the same |
| bo, all three | `cargos(first: 10)` | 3 errors, one per edge, `SERVICE_UNAVAILABLE`; all three nodes null | 1 error at `["cargos","edges",2,"node"]`; nodes `XYZ789`, `STU678`, null |
| bo, ACME's objects | `cargo(ABC123)`, `node(cargo_ABC123)`, `node(evt_1)` | null, no errors | the same |
| bo, `nodes` | `cargo_ABC123`, `cargo_XYZ789`, `evt_1`, `evt_3` | `[null, Cargo XYZ789, null, null]` | the same |
| ops | `cargos(first: 10) { totalCount }` | 6 | the same |
| ana, `registrationTime` | `handlingHistory(first: 2)` on ABC123 | 2 errors at `[..., "edges", 0\|1, "node", "registrationTime"]`, `FORBIDDEN`, `operator role required`; both `node` null; both cursors present | the same |
| | `node(id: "evt_1") { ... on HandlingEvent { registrationTime } }` | `data.node` null; error at `["node","registrationTime"]` | the same |
| ana without the field | `id`, `completionTime` | `evt_2`, `evt_1`, no errors | the same |
| ops, `registrationTime` | the same history | `2026-10-01T08:35:00Z`, `2026-09-30T16:05:00Z` | the same |
| ana, write | `registerHandlingEvent` | `data` null; error at `["registerHandlingEvent"]`, `FORBIDDEN`; 0 source calls | the same |
| anonymous, write | the same | code `UNAUTHENTICATED`; 0 source calls | the same |
| ops, write | UNLOAD ABC123 at DEHAM on V100S | `evt_10`; `IN_PORT`; one `handling.appendEvent` | the same |
| tampered signature, tampered payload, wrong audience, malformed token, expired token | any operation, even a public one | HTTP 401, `WWW-Authenticate: Bearer`, no GraphQL body | HTTP 401, `WWW-Authenticate: Bearer error="invalid_token"`, `{"detail":"invalid token"}` |
| concurrent callers | six ana and six bo `cargos` requests together | each gets only its own cargos | the same |
| schema | anonymous introspection | conforms to `contracts/schema/`; `finalArrivalDate` deprecated; only `Subscription` unserved | the same |

## Code-first notes

These checks ran on the pinned versions (Quarkus 3.40.1 with `quarkus-oidc`, SmallRye GraphQL 2.18.5;
Strawberry 0.335.0, PyJWT 2.15.1, Keycloak 26.8.1).

**Error codes and messages on SmallRye.** `@Authenticated` and `@RolesAllowed` fail with Quarkus's
`UnauthorizedException` and `ForbiddenException`. SmallRye reports them at the operation's path, and
`DeclaredErrorCodeProvider` maps exceptions to a code. `SecurityErrorTranslator`, a small CDI interceptor
that runs outside Quarkus's own security interceptor, swaps them for `AuthenticationRequiredException` and
`OperatorRoleRequiredException`, two `@ErrorCode` exceptions in the same allowlist as `SourceUnavailableException`.
The access check stays the framework's. Every `ForbiddenException` maps to "operator role required", because in this example the operator role is the only one that can refuse. `SecurityErrorTranslator` gives both refusals the contract's messages. With the swap the two stacks answer with identical messages.

**`@RolesAllowed` on a `@Source` method.** It works: the denial is an error at the field's path
(`...,"node","registrationTime"`), and the nullable `node` above it becomes null. The `registrationTime`
component of the `HandlingEvent` record is `@Ignore`d, and the secured field is a method in `HandlingApi`.

**Identity in async and batch resolvers.** `Viewers.current()` reads `SecurityIdentity` at resolver entry. It
returned the right caller in `Uni` resolvers, in the `@Source List` batch resolvers (`CargoEdge.node`,
`HandlingEvent.cargo`) that run after a source's latency, and with twelve requests from two callers in flight
together (`verify.sh` case 10).

**The challenge header.** Quarkus answers a bad token with `401` and `WWW-Authenticate: Bearer` and an empty
body; PyJWT's failure is mapped to `Bearer error="invalid_token"` (RFC 6750) with the body
`{"detail":"invalid token"}`. `verify.sh` asserts the exact header and body on each stack. A public field is refused too: a
presented token is validated whatever the operation.

**Tampering.** `verify.sh` changes a character in the middle of the signature, so the signature bytes
change, and also rewrites the payload's role to `operator` with the original signature.

**Permission classes on Strawberry.** `permission_classes=[IsAuthenticated, IsOperator]` runs the classes in
order, so an anonymous caller gets `UNAUTHENTICATED` and a shipper gets `FORBIDDEN`. The default error of a
permission is a `StrawberryGraphQLError`, which Chapter 9's `should_mask` would mask, so each class overrides
`on_unauthorized` to raise an `ExposedError` subclass. A field with a failing permission and a non-null type
nulls its nearest nullable parent.

**The ownership rule.** `BookingSource` is the only class that reads the owner. It checks before it loads, so a
cargo another shipper owns is null even when its load would fail (`GHI345` for ana), and `cargos` filters the
booking index before paging, so `totalCount`, `hasNextPage` and the cursors describe the caller's view. `node`
for an `evt_` id asks the booking source about the event's cargo.

**Failing batch on Quarkus.** bo's three-cargo page includes `GHI345`, whose load fails. As in Chapter 13, SmallRye
fails the whole batch, so all three nodes are null; Strawberry fails one key.

**The issuer.** Tokens carry the address they were requested at. Both stacks pin
`http://localhost:8282/realms/shipping` and fetch keys from `keycloak:8080` with discovery off
(`quarkus.oidc.discovery-enabled=false`, `PyJWKClient(...)`).

**Python.** `Authenticator` (in `app/auth.py`) lives on the application state, so the JWKS cache is shared. The
blocking key fetch runs in a thread pool. `TrackingContext.identity` is the only authentication state; the token
is not kept.

## Diagram

`architecture.svg` / `architecture.excalidraw` (regenerate with
`python3 -I diagrams/examples/18-authn-authz-architecture.py`) show the compose topology: a client sending a
bearer token to each stack, Keycloak issuing tokens and serving keys, both stacks diffed anonymously against the
canonical SDL, and the opt-in `compose.observability.yaml` override.
