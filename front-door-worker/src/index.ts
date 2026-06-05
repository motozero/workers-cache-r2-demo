// Front-door worker (orchestrator). NOT cached. It normalizes each request into
// one canonical key, carries it as the forwarded path, and calls the cached
// worker over a service binding. Workers Cache fronts that callee, so on a HIT
// the cached worker never runs.
export default {
  async fetch(
    req: Request,
    env: { CACHE_WORKER: { fetch: (req: Request) => Promise<Response> } },
  ): Promise<Response> {
    const url = new URL(req.url);
    const lang = (req.headers.get("Accept-Language") || "en").split(",")[0].trim();

    // Build the single canonical key once and carry it as the path. The same
    // string becomes the Workers Cache key and the R2 object key downstream.
    url.pathname = `/${lang}${url.pathname}`;

    return env.CACHE_WORKER.fetch(new Request(url.toString(), req));
  },
};
