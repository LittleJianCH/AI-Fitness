import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

// The pinned Servant generator emits 3.0. Convert Schema Objects, not arbitrary
// JSON: example payloads and property names must retain their original meaning.
export function upgradeSchema(input) {
  if (typeof input === 'boolean') return input;
  const schema = { ...input };
  // openapi3 describes Aeson's UTC codec using a strftime-like custom format.
  // The bytes are RFC 3339; expose the standard format to client generators.
  if (schema.format === 'yyyy-mm-ddThh:MM:ssZ') schema.format = 'date-time';
  const nullable = schema.nullable;
  delete schema.nullable;
  for (const bound of ['minimum', 'maximum']) {
    const exclusive = `exclusive${bound[0].toUpperCase()}${bound.slice(1)}`;
    if (schema[exclusive] === true) {
      if (typeof schema[bound] !== 'number') throw new Error(`${exclusive} needs ${bound}`);
      schema[exclusive] = schema[bound];
      delete schema[bound];
    } else if (schema[exclusive] === false) {
      delete schema[exclusive];
    }
  }
  if (Array.isArray(schema.items)) throw new Error('Tuple schemas require an explicit 3.1 representation');
  if (schema.properties) schema.properties = Object.fromEntries(
    Object.entries(schema.properties).map(([key, value]) => [key, upgradeSchema(value)]),
  );
  for (const key of ['allOf', 'anyOf', 'oneOf']) {
    if (schema[key]) schema[key] = schema[key].map(upgradeSchema);
  }
  for (const key of ['items', 'additionalProperties', 'not']) {
    if (schema[key] !== undefined) schema[key] = upgradeSchema(schema[key]);
  }
  if (nullable === true) {
    if (!schema.type) throw new Error('Nullable without an explicit type is not supported by this bridge');
    // 3.0 nullable changes the type constraint; other constraints (e.g. enum)
    // still apply. A union of types preserves that behavior.
    schema.type = [schema.type, 'null'];
  }
  return schema;
}

function upgradeContainer(value) {
  if (Array.isArray(value)) return value.map(upgradeContainer);
  if (!value || typeof value !== 'object' || JSON.isRawJSON(value)) return value;
  return Object.fromEntries(Object.entries(value).map(([key, child]) => [key,
    key === 'schema' ? upgradeSchema(child)
      : ['example', 'examples', 'default'].includes(key) ? child : upgradeContainer(child),
  ]));
}

export function upgradeDocument(input) {
  if (!/^3\.0\./.test(input.openapi)) throw new Error('Expected the pinned Servant OpenAPI 3.0 output');
  const output = upgradeContainer(input);
  output.openapi = '3.1.0';
  output.jsonSchemaDialect = 'https://spec.openapis.org/oas/3.1/dialect/base';
  output.components.schemas = Object.fromEntries(
    Object.entries(input.components.schemas).map(([key, schema]) => [key, upgradeSchema(schema)]),
  );
  for (const [path, pathItem] of Object.entries(output.paths)) {
    for (const [method, operation] of Object.entries(pathItem)) {
      if (!['get', 'post', 'put', 'patch', 'delete'].includes(method)) continue;
      operation.operationId = `${method}_${path.slice('/api/v1/'.length).replace(/[{}]/g, '').replaceAll(/[-/]/g, '_')}`;
      // UVerb wraps NoContent in WithStatus; the upstream generator then emits
      // a body schema even though the actual MIME renderer produces no body.
      if (operation.responses['204']) delete operation.responses['204'].content;
      // Servant may reject a request before entering its typed handler (e.g.
      // unsupported media type). Future middleware must use the same envelope.
      operation.responses.default = {
        description: 'An API error; inspect code rather than matching the human-readable message.',
        content: { 'application/json': { schema: { $ref: '#/components/schemas/Problem' } } },
      };
    }
  }
  return output;
}

export function parseDocument(text) {
  // Preserve int64 schema bounds exactly through JavaScript serialization.
  // Their numeric literals otherwise round and can become invalid Swift bounds.
  return JSON.parse(text, (_key, value, context) =>
    typeof value === 'number' && Number.isInteger(value) && !Number.isSafeInteger(value)
      ? JSON.rawJSON(context.source) : value,
  );
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const input = parseDocument(await readFile('../backend/build/openapi-3.0.json', 'utf8'));
  await mkdir('build', { recursive: true });
  await writeFile('build/openapi.json', `${JSON.stringify(upgradeDocument(input), null, 2)}\n`);
}
