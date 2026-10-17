// Ch23 Testing GraphQL APIs - the load runs.
//
// Each run sends the shared client documents (/documents) to one server and
// checks the GraphQL body of every response, not the status line. The runs use
// the shared-iterations executor, so the number of requests is exact; the
// thresholds assert correctness only: no transport failure, every check true,
// every iteration done. Latency is reported in the summary and never asserted.
//
//   TARGET  the GraphQL URL, for example http://quarkus:8080/graphql
//   RUN     fanout | cost | retry | mix
//   STACK   quarkus | python (the partial-failure shape of ListCargos differs)
//
// Run it with:  k6 run --quiet /scripts/tracking.js
import http from 'k6/http';
import exec from 'k6/execution';
import { check } from 'k6';

const TARGET = __ENV.TARGET || 'http://localhost:8080/graphql';
const RUN = __ENV.RUN || 'fanout';
const STACK = __ENV.STACK || 'quarkus';

const FAN_OUT = open('/documents/fan-out.graphql');
const OVER_BUDGET = open('/documents/load/over-budget.graphql');
const TRACK_CARGO = open('/documents/track-cargo.graphql');
const TRACK_CARGO_BRIEF = open('/documents/track-cargo-brief.graphql');
const LIST_CARGOS = open('/documents/list-cargos.graphql');
const REGISTER_HANDLING = open('/documents/register-handling.graphql');

// The registration every retry sends: one UNLOAD of ABC123 at Hamburg. The
// server issues its first event id of the run, evt_10.
const REGISTRATION = {
  trackingId: 'ABC123',
  type: 'UNLOAD',
  location: 'DEHAM',
  voyageNumber: 'V100S',
  completionTime: '2026-10-09T15:00:00Z',
  idempotencyKey: 'ch23-load-a1',
};
const REGISTERED_EVENT = 'evt_10';

// Quarkus resolves a page's nodes in one bulk call, so the booking outage
// reaches all six nodes; Strawberry fails only the one key.
const LIST_CARGOS_ERRORS = STACK === 'quarkus' ? 6 : 1;
const OVER_BUDGET_MESSAGE = 'maximum query complexity exceeded 7651 > 1000';

const HEADERS = { 'Content-Type': 'application/json', 'X-Client-Name': 'ch23-load' };

const shared = (vus, iterations, execName) => ({
  executor: 'shared-iterations',
  vus,
  iterations,
  maxDuration: '5m',
  exec: execName,
});

const RUNS = {
  fanout: {
    iterations: 160,
    scenarios: { fanout: shared(8, 160, 'fanOut') },
  },
  cost: {
    iterations: 160,
    scenarios: {
      accepted: shared(4, 80, 'fanOut'),
      refused: shared(4, 80, 'overBudget'),
    },
  },
  retry: {
    iterations: 40,
    scenarios: { retry: shared(8, 40, 'retry') },
  },
  mix: {
    iterations: 120,
    scenarios: { mix: shared(8, 120, 'mix') },
  },
};

if (!(RUN in RUNS)) {
  throw new Error(`unknown RUN ${RUN}; expected one of ${Object.keys(RUNS).join(', ')}`);
}

export const options = {
  scenarios: RUNS[RUN].scenarios,
  thresholds: {
    http_req_failed: ['rate==0'],
    checks: ['rate==1'],
    iterations: [`count==${RUNS[RUN].iterations}`],
  },
};

function send(query, variables) {
  const res = http.post(TARGET, JSON.stringify({ query, variables }), { headers: HEADERS });
  let body = null;
  try {
    body = res.json();
  } catch (e) {
    body = null;
  }
  return { res, body };
}

export function fanOut() {
  const { res, body } = send(FAN_OUT);
  check(res, {
    'FanOut answers 200 with a GraphQL body': () => res.status === 200 && body !== null,
    'FanOut has no errors': () => body !== null && body.errors === undefined,
    'FanOut returns four cargos': () => body !== null && body.data.cargos.edges.length === 4,
    'FanOut derives a transport status for every cargo': () =>
      body !== null && body.data.cargos.edges.every((e) => !!e.node.delivery.transportStatus),
  });
}

export function overBudget() {
  const { res, body } = send(OVER_BUDGET);
  check(res, {
    'OverBudget answers 200 with a GraphQL body': () => res.status === 200 && body !== null,
    'OverBudget carries no data': () => body !== null && !body.data,
    'OverBudget is refused with one error': () => body !== null && body.errors.length === 1,
    'OverBudget states its price': () => body !== null && body.errors[0].message === OVER_BUDGET_MESSAGE,
  });
}

export function retry() {
  const { res, body } = send(REGISTER_HANDLING, { input: REGISTRATION });
  check(res, {
    'RegisterHandling answers 200 with a GraphQL body': () => res.status === 200 && body !== null,
    'RegisterHandling has no errors': () => body !== null && body.errors === undefined,
    'RegisterHandling answers every retry with the same event': () =>
      body !== null && body.data.registerHandlingEvent.handlingEvent.id === REGISTERED_EVENT,
    'RegisterHandling reports no user errors': () =>
      body !== null && body.data.registerHandlingEvent.userErrors.length === 0,
  });
}

export function mix() {
  const turn = exec.scenario.iterationInTest % 3;
  if (turn === 0) {
    const { res, body } = send(TRACK_CARGO, { id: 'ABC123' });
    check(res, {
      'TrackCargo has no errors': () => body !== null && body.errors === undefined,
      'TrackCargo returns ABC123': () => body !== null && body.data.cargo.trackingId === 'ABC123',
    });
  } else if (turn === 1) {
    const { res, body } = send(TRACK_CARGO_BRIEF, { id: 'ABC123' });
    check(res, {
      'TrackCargoBrief has no errors': () => body !== null && body.errors === undefined,
      'TrackCargoBrief reflects the registered event': () =>
        body !== null && body.data.cargo.delivery.transportStatus === 'IN_PORT',
    });
  } else {
    const { res, body } = send(LIST_CARGOS);
    check(res, {
      'ListCargos returns six edges': () => body !== null && body.data.cargos.edges.length === 6,
      'ListCargos reports the booking outage per node': () =>
        body !== null && body.errors.length === LIST_CARGOS_ERRORS,
      'ListCargos errors carry SERVICE_UNAVAILABLE': () =>
        body !== null && body.errors.every((e) => e.extensions.code === 'SERVICE_UNAVAILABLE'),
    });
  }
}

// The end-of-test summary as one JSON document on stdout: the counts the
// thresholds judged, and the latency, which is for the reader.
export function handleSummary(data) {
  const m = data.metrics;
  const summary = {
    run: RUN,
    stack: STACK,
    iterations: m.iterations.values.count,
    requests: m.http_reqs.values.count,
    checks: { rate: m.checks.values.rate, passes: m.checks.values.passes, fails: m.checks.values.fails },
    http_req_failed: m.http_req_failed.values.rate,
    latency_ms: {
      med: Math.round(m.http_req_duration.values.med),
      p95: Math.round(m.http_req_duration.values['p(95)']),
    },
  };
  return { stdout: JSON.stringify(summary) + '\n' };
}
