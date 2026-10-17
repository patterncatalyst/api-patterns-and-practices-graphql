import graphqlPlugin from '@graphql-eslint/eslint-plugin';

export default [
  {
    files: ['schema/**/*.graphql'],
    languageOptions: { parser: graphqlPlugin.parser },
    plugins: { '@graphql-eslint': graphqlPlugin },
    rules: {
      ...graphqlPlugin.configs['flat/schema-recommended'].rules,
      // The recommended preset only requires descriptions on types and root
      // fields; the contract documents every field, argument and enum value too.
      '@graphql-eslint/require-description': [
        'error',
        {
          types: true,
          rootField: true,
          DirectiveDefinition: true,
          FieldDefinition: true,
          InputValueDefinition: true,
          EnumValueDefinition: true,
        },
      ],
      // Only entities (Node implementers) carry identity; value objects, Relay
      // connection/edge types, payloads and errors intentionally have no id.
      '@graphql-eslint/strict-id-in-types': [
        'error',
        {
          exceptions: {
            suffixes: ['Connection', 'Edge', 'Payload', 'Error', 'Info'],
            types: [
              'CarrierMovement',
              'Delivery',
              'HandlingActivity',
              'Itinerary',
              'Leg',
              'RouteSpecification',
            ],
          },
        },
      ],
    },
  },
];
