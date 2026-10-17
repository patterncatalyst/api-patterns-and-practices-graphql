import type { CodegenConfig } from "@graphql-codegen/cli";

// The same schema and preset as codegen.ts, pointed at a document that selects a
// field the contract does not have. `npm run codegen:check` exits non-zero.
const config: CodegenConfig = {
  schema: "/schema/**/*.graphql",
  documents: ["fixtures/**/*.graphql"],
  generates: {
    "/tmp/codegen-check/": { preset: "client" },
  },
};

export default config;
