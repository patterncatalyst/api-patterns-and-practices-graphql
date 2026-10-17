// Ch22 Client integration - Apollo Client with a normalized cache, headless in Node.
//
// Usage: node src/main.ts <graphql-url>
//
// The operations live in operations.graphql. GraphQL Code Generator's client
// preset turns them into typed documents (src/gql/graphql.ts), so every result
// below is typed from the contract.
import { ApolloClient, HttpLink, InMemoryCache } from "@apollo/client";

import {
  ListCargosDocument,
  RegisterHandlingDocument,
  TrackCargoBriefDocument,
  TrackCargoDocument,
} from "./gql/graphql.ts";

const url = process.argv[2];
if (!url) {
  console.error("usage: node src/main.ts <graphql-url>");
  process.exit(2);
}

// HttpLink takes the fetch implementation as an option; wrapping the global one
// counts every request that leaves the client.
let fetches = 0;
const countingFetch: typeof fetch = (input, init) => {
  fetches += 1;
  return fetch(input, init);
};

const cache = new InMemoryCache({
  typePolicies: {
    // Delivery has no id of its own. Merging lets a response that selects some of
    // its fields update the same stored object instead of replacing it.
    Delivery: { merge: true },
  },
});

const client = new ApolloClient({
  link: new HttpLink({
    uri: url,
    fetch: countingFetch,
    headers: { "X-Client-Name": "ch22-js", "X-Client-Version": "1.0.0" },
  }),
  cache,
});

const print = (line: Record<string, unknown>): void => {
  console.log(JSON.stringify(line));
};

// 1. A first query goes to the server and fills the cache.
const track = await client.query({ query: TrackCargoDocument, variables: { id: "ABC123" } });
print({ step: "track", status: track.data?.cargo?.delivery.transportStatus, fetches });

// 2. A second query whose fields are all cached is answered without a request.
const brief = await client.query({ query: TrackCargoBriefDocument, variables: { id: "ABC123" } });
print({ step: "brief", status: brief.data?.cargo?.delivery.transportStatus, fetches });

// 3. The cache holds one entry per object, keyed by __typename and id.
const keys = Object.keys(cache.extract());
print({
  step: "normalized",
  cargoKeys: keys.filter((key) => key.startsWith("Cargo:")),
  locationKeys: keys.filter((key) => key.startsWith("Location:")).sort(),
});

// 4. The mutation payload names the cargo and the field that changed; the cache
//    merges it into the same entry, and a cache-only read of the first query sees it.
const registered = await client.mutate({
  mutation: RegisterHandlingDocument,
  variables: {
    input: {
      trackingId: "ABC123",
      type: "UNLOAD",
      location: "DEHAM",
      voyageNumber: "V100S",
      completionTime: "2026-10-09T15:00:00Z",
    },
  },
});
const fromCache = client.readQuery({ query: TrackCargoDocument, variables: { id: "ABC123" } });
print({
  step: "after-mutation",
  event: registered.data?.registerHandlingEvent.handlingEvent?.id,
  userErrors: registered.data?.registerHandlingEvent.userErrors.length,
  status: fromCache?.cargo?.delivery.transportStatus,
  fetches,
});

// 5. A response with data and errors. With errorPolicy "all" the promise resolves
//    with both: `data` holds the nodes that loaded and `error` holds the errors.
const page = await client.query({ query: ListCargosDocument, errorPolicy: "all", fetchPolicy: "network-only" });
const edges = page.data?.cargos.edges ?? [];
print({
  step: "partial",
  edges: edges.length,
  nullNodes: edges.filter((edge) => edge.node === null).length,
  error: page.error?.name,
  errors: page.error && "errors" in page.error ? (page.error.errors as unknown[]).length : 0,
  fetches,
});
