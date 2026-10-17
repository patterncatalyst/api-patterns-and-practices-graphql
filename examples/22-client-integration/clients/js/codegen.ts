import type { CodegenConfig } from "@graphql-codegen/cli";

// The schema is the canonical SDL. The image build receives it as the `schema`
// build context (compose: build.additional_contexts) and places it at /schema,
// so the client never carries a copy of contracts/schema/.
const config: CodegenConfig = {
  schema: "/schema/**/*.graphql",
  documents: ["src/**/*.graphql"],
  generates: {
    "src/gql/": {
      preset: "client",
      presetConfig: { fragmentMasking: false },
      config: {
        useTypeImports: true,
        enumsAsTypes: true,
        importExtension: ".ts",
        scalars: { TrackingId: "string", UnLocode: "string", DateTime: "string" },
      },
    },
  },
  // A document that no longer matches the schema stops the run.
  ignoreNoDocuments: false,
};

export default config;
