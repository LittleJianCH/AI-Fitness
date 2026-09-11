// Select only the read operations used by the demo. Orval 7.13's Zod renderer
// looks up application/json literally and misses Servant's charset suffix.
module.exports = (document) => ({
  ...document,
  paths: Object.fromEntries(
    ['/api/v1/workouts', '/api/v1/workouts/{workoutId}'].map((path) => {
      const get = document.paths[path]?.get;
      if (!get) throw new Error(`Missing read contract: ${path}`);
      return [path, { get: {
        ...get,
        responses: Object.fromEntries(Object.entries(get.responses).map(([status, response]) => [status, {
          ...response,
          ...(response.content ? { content: Object.fromEntries(Object.entries(response.content).map(([media, schema]) => [
            media.split(';')[0].trim(), schema,
          ])) } : {}),
        }])),
      } }];
    }),
  ),
});
