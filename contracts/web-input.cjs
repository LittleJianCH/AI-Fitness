// Select implemented browser operations. Orval's Zod renderer looks up
// application/json literally and misses Servant's charset suffix.
const operations = {
  '/auth/policy': ['get'],
  '/auth/web/csrf': ['get'],
  '/auth/web/login': ['post'],
  '/auth/register': ['post'],
  '/me': ['get'],
  '/auth/logout': ['post'],
  '/auth/sessions': ['get', 'delete'],
  '/auth/sessions/{sessionId}': ['delete'],
  '/auth/password': ['put'],
  '/imports/fit': ['post'],
  '/imports/{importId}': ['get'],
  '/workouts': ['get', 'post'],
  '/workouts/{workoutId}': ['get', 'delete'],
  '/workouts/{workoutId}/power-curve': ['get'],
  '/workouts/{workoutId}/user-data': ['put'],
};
const content = (value) => ({
  ...value,
  ...(value.content ? { content: Object.fromEntries(Object.entries(value.content).map(([media, schema]) => [
    media.split(';')[0].trim(), schema,
  ])) } : {}),
});
module.exports = (document) => ({
  ...document,
  paths: Object.fromEntries(Object.entries(operations).map(([suffix, methods]) => {
    const path = `/api/v1${suffix}`;
    return [path, Object.fromEntries(methods.map((method) => {
      const operation = document.paths[path]?.[method];
      if (!operation) throw new Error(`Missing browser contract: ${method} ${path}`);
      return [method, {
        ...operation,
        ...(operation.requestBody ? { requestBody: content(operation.requestBody) } : {}),
        responses: Object.fromEntries(Object.entries(operation.responses).map(([status, response]) => [status, content(response)])),
      }];
    }))];
  })),
});
