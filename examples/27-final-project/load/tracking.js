// Ch27 The final project - the load runs through the edge (Chapter 23's runs, reduced to two).
//
// Each run sends a shared client document to the edge with an operator's bearer
// token and checks the GraphQL body of every response, not the status line. The
// runs use the shared-iterations executor, so the number of requests is exact;
// the thresholds assert correctness only: no transport failure, every check
// true, every iteration done. Latency is in the summary and is never asserted.
//
//   TARGET  the edge's GraphQL URL, for example https://edge:8443/graphql
//   RUN     fanout | cost
//   TOKEN   a bearer token for an operator
//
// Run it with:  k6 run --quiet /scripts/tracking.js
import http from 'k6/http';
import { check } from 'k6';

const TARGET = __ENV.TARGET || 'https://edge:8443/graphql';
const RUN = __ENV.RUN || 'fanout';
const TOKEN = __ENV.TOKEN || '';

const FAN_OUT = open('/documents/fan-out.graphql');
const OVER_BUDGET = open('/documents/over-budget.graphql');

const OVER_BUDGET_MESSAGE = 'maximum query complexity exceeded 7651 > 1000';

const HEADERS = {
  'Content-Type': 'application/json',
  'X-Client-Name': 'ch27-load',
  Authorization: `Bearer ${TOKEN}`,
};

const shared = (vus, iterations, execName) => ({
  executor: 'shared-iterations',
  vus,
  iterations,
  maxDuration: '5m',
  exec: execName,
});

const RUNS = {
  fanout: {
    iterations: 80,
    scenarios: { fanout: shared(8, 80, 'fanOut') },
  },
  cost: {
    iterations: 80,
    scenarios: {
      accepted: shared(4, 40, 'fanOut'),
      refused: shared(4, 40, 'overBudget'),
    },
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

function send(query) {
  const res = http.post(TARGET, JSON.stringify({ query }), { headers: HEADERS });
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

// The end-of-test summary as k6's own summary object on one stdout line: the
// harness reads metrics.iterations.values.count and metrics.checks.values.rate.
export function handleSummary(data) {
  return { stdout: JSON.stringify(data) + '\n' };
}
