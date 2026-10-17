# Contracts — the canonical GraphQL SDL

The `.graphql` files under `schema/` are the contract for the tracking view of the
shipping domain. Both implementations (Quarkus SmallRye GraphQL and Python
Strawberry) are **code-first**: each builds its schema from annotated code or
decorated classes, exports it as SDL, and that export is diff-checked against this
canonical schema. CI gates every change to the canonical SDL itself with
[GraphQL ESLint](https://the-guild.dev/graphql/eslint) and
[GraphQL Inspector](https://the-guild.dev/graphql/inspector), both open source.

```
schema/shipping/
  scalars.graphql    DateTime, TrackingId, UnLocode scalars; Node interface; PageInfo
  location.graphql   Location (UN/LOCODE port or terminal)
  voyage.graphql     Voyage, CarrierMovement
  cargo.graphql      Cargo, RouteSpecification, Itinerary, Leg, Delivery,
                     TransportStatus, RoutingStatus, CargoConnection, CargoEdge
  handling.graphql   HandlingEvent, HandlingEventType, HandlingEvent connection,
                     RegisterHandlingEventInput/Payload, UserError
  schema.graphql     schema { query mutation subscription }, Query, Mutation, Subscription
```

## Design notes

- GraphQL is the aggregation view: nearly all surface is `Query`. The one mutation
  (`registerHandlingEvent`) and one subscription (`cargoHandled`) support Ch8 and Ch21.
- Nullability is deliberate. Fields the domain guarantees are non-null
  (`Cargo.trackingId`, `Leg.loadLocation`). Fields resolved from another service or
  that may not exist yet are nullable (`Cargo.itinerary`, `Leg.voyage`,
  `Delivery.estimatedTimeOfArrival`), so a downstream failure nulls one field, not
  the whole response (Ch4).
- Lists paginate with Relay cursor connections (`first`/`after`, `last`/`before`).
- `Node` plus `Query.node(id:)` implements Relay Global Object Identification.
- Mutations return a payload with a `UserError` list for domain failures; transport
  and system failures use the top-level `errors` array (Ch9).
- Field names are camelCase, types PascalCase, enum values SCREAMING_SNAKE_CASE;
  every type and field has a description.

## The gates (run in CI, runnable locally)

```bash
cd contracts
npm ci                       # pinned tooling; Node 24 LTS
npm run lint                 # graphql-eslint schema-recommended rules
npm run breaking             # GraphQL Inspector diff against origin/main
```

`npm run breaking` is the evolution gate, the analog of `buf breaking` in the gRPC
book. It extracts `contracts/schema/` from the base ref (default `origin/main`,
override with `BASE_REF=<ref>`), then runs `graphql-inspector diff` between that
copy and the working tree. When the base ref has no schema yet (the first
introduction), the gate prints a message and skips; a base ref that does not resolve
(not fetched) is an error, so the gate never passes by accident. No hosted registry is used.

### Rules

GraphQL Inspector classifies each change as breaking, dangerous or safe:

| Class | Examples in this schema | Default gate |
|---|---|---|
| Breaking | a removed field or enum value; a loosened output type (`TrackingId!` to `TrackingId`); a new required input field; the removal of a deprecated field | exit 1 |
| Dangerous | an enum value added to an existing enum; an optional argument added to an existing field | exit 0, plus a PR warning |
| Safe | an added field, type or optional input field; a tightened output; a field newly deprecated | exit 0 |

Exit codes: `0` passed or skipped, `1` a breaking change, `2` the base ref does not
resolve.

### Environment

| Variable | Meaning |
|---|---|
| `BASE_REF` | Git ref to compare against (default `origin/main`). |
| `BASE_DIR` | A directory of `.graphql` files used as the base instead of a git ref. This is how the gate itself is tested. |
| `NEW_DIR` | The new side, a directory of `.graphql` files (default `schema`, the working tree). |
| `BREAKING_RULES` | Comma-separated Inspector rule names, each passed as a repeated `--rule`. Default: none. |

```bash
# the real change against a saved copy of the old schema
BASE_DIR=/tmp/old/schema npm --prefix contracts run breaking

# two fixture directories, with a rule
BASE_DIR=fixtures/base NEW_DIR=fixtures/new BREAKING_RULES=dangerousBreaking \
  npm --prefix contracts run breaking
```

### Dangerous changes

Dangerous changes are routine evolution that needs a reviewer's eye, not a red build.
The policy:

- The default CI gate **fails only on breaking changes**.
- Every dangerous change is surfaced on the pull request. With `GITHUB_ACTIONS=true` the
  script echoes each dangerous line as `::warning title=Dangerous schema change::<line>`,
  which GitHub shows as an annotation without failing the job.
- `BREAKING_RULES=dangerousBreaking` is an opt-in **strict mode** that fails on dangerous
  changes too.
- Removing a deprecated field stays **breaking**. A pull request that removes
  one, after usage evidence shows no client reads it, sets
  `BREAKING_RULES=suppressRemovalOfDeprecatedField` to downgrade that removal.
