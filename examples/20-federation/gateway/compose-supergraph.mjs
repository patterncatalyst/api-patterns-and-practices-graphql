// Composition is a build step: it reads each subgraph's schema, composes the
// supergraph, and writes one file that the gateway loads. Nothing here runs in
// the request path. A subgraph is named by --subgraph name=url (its live
// `_service { sdl }`) or --file name=path (an SDL file, as the failure fixtures
// use). Any composition error is printed as `<code>: <message>` and the exit
// status is 1, so a pipeline stops before a broken supergraph is deployed.
import { readFileSync, writeFileSync } from 'node:fs';
import { parseArgs } from 'node:util';
import { parse } from 'graphql';
import { composeServices } from '@theguild/federation-composition';

const { values } = parseArgs({
  options: {
    out: { type: 'string' },
    subgraph: { type: 'string', multiple: true, default: [] },
    file: { type: 'string', multiple: true, default: [] },
  },
});

const split = (entry) => {
  const at = entry.indexOf('=');
  return [entry.slice(0, at), entry.slice(at + 1)];
};

async function liveSdl(url) {
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ query: '{ _service { sdl } }' }),
  });
  const body = await response.json();
  return body.data._service.sdl;
}

const services = [];
for (const entry of values.subgraph) {
  const [name, url] = split(entry);
  services.push({ name, url, typeDefs: parse(await liveSdl(url)) });
}
for (const entry of values.file) {
  const [name, path] = split(entry);
  services.push({ name, url: `http://${name}/graphql`, typeDefs: parse(readFileSync(path, 'utf8')) });
}

const result = composeServices(services);
if (result.errors?.length) {
  for (const error of result.errors) {
    console.log(`${error.extensions?.code ?? 'COMPOSITION_ERROR'}: ${error.message}`);
  }
  process.exit(1);
}
writeFileSync(values.out, result.supergraphSdl);
console.log(`composed ${services.map((s) => s.name).join(' + ')} -> ${values.out}`);
