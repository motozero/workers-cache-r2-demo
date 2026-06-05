// Cached worker. With `cache.enabled` set in wrangler config, Workers Cache sits
// in front of this worker, so a cache HIT returns the response without executing
// this code at all. On a MISS the worker runs once: it checks R2 (the durable
// tier) using the request path as the key, generates and stores content on an R2
// miss, and returns a cacheable response.
//
// The request path is the single canonical key (set upstream by the front-door
// worker) and is used for BOTH the Workers Cache key and the R2 object key.
export default {
  async fetch(req: Request, env: { SNAPSHOTS: any }): Promise<Response> {
    const key = new URL(req.url).pathname.replace(/^\/+/, "");

    // runId is regenerated every time this code runs. Across Workers Cache HITs
    // the worker does not run, so runId stays identical. That is the proof.
    const runId = crypto.randomUUID();

    const object = await env.SNAPSHOTS.get(key);
    if (object === null) {
      const generated = `generated content for /${key} @ ${new Date().toISOString()}`;
      await env.SNAPSHOTS.put(key, generated);
      return reply(generated, runId, "origin", key);
    }
    return reply(await object.text(), runId, "r2", key);
  },
};

function reply(body: string, runId: string, source: string, key: string): Response {
  return new Response(body, {
    headers: {
      "content-type": "text/plain",
      "cache-control": "public, max-age=120",
      "x-run-id": runId,
      "x-source": source,
      "x-cache-key": key,
    },
  });
}
