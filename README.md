# Workers Cache + R2: cache in front of a Worker

A small, self-contained demo of caching a Cloudflare Worker's output with
**Workers Cache**, so the Worker runs only on a cache miss, with a durable
**R2** tier behind it. One canonical key drives both the cache and the R2
object, so there is nothing to keep in sync.

## See it work in 30 seconds (no Cloudflare account needed)

Clone this repo and run the included script. It hits the live reference
deployment, so no setup is required:

```sh
./demo.sh
```

You will see four numbered steps. The proof you are looking for is in Step 2:

- **Step 1** — first call to a fresh path: `cf-cache-status: MISS`, a fresh `x-run-id`.
- **Step 2** — same URL again: `cf-cache-status: HIT`, the **same** `x-run-id`.

That unchanged `x-run-id` is the headline. The cached worker generates a new
`x-run-id` on every actual execution. If the same id comes back, the worker
did not execute — Workers Cache served the response directly.

Steps 3 and 4 sanity-check that the response bodies are byte-identical and that
a different path is its own cache entry (fresh MISS, different `x-run-id`).

If you prefer raw curl:

```sh
URL="https://front-door-worker.laboratory.workers.dev/anything-$(date +%s)"
curl -sD - -o /dev/null "$URL" | grep -iE 'cf-cache-status|x-run-id'
curl -sD - -o /dev/null "$URL" | grep -iE 'cf-cache-status|x-run-id'
```

To run the demo against your own deployment after you deploy (see below):

```sh
FDW=https://front-door-worker.<your-subdomain>.workers.dev ./demo.sh
```

## What this demo shows

- **Workers Cache fronts a Worker.** On a hit, Cloudflare returns the cached
  response without executing the Worker at all.
- **Called over a service binding.** A front-door Worker normalizes each request
  and forwards it to the cached worker; the callee's cache is consulted first.
- **One key, no drift.** The front-door Worker builds a single canonical key and
  carries it as the request path. That same string is the Workers Cache key and
  the R2 object key.
- **Durable second tier.** On a cache miss the worker checks R2 before doing any
  real work, so long-tail content survives edge eviction.

## Architecture

```
eyeball
  -> front-door-worker          (not cached; normalizes -> canonical path)
       -> [service binding]
            -> Workers Cache     (hit: return cached, the worker does NOT run)
                 -> cache-worker (miss: check R2 -> generate -> store)
                      -> R2 bucket
```

## Layout

- `demo.sh` — runs the four-step proof against the live deployment, or against
  your own when you set the `FDW` env var.
- `front-door-worker/` — orchestrator, not cached, builds the canonical key.
- `cache-worker/` — `cache.enabled`, R2-bound, runs only on a miss. No public
  URL; reachable only via the service binding.

## Deploy your own copy

### Prerequisites

- A Cloudflare account with Workers Cache available (`cache.enabled`) and R2 enabled.
- Wrangler 4.69.0 or newer.

### Steps

```sh
npm install                                            # installs wrangler locally
npx wrangler r2 bucket create cache-worker-snapshots

cd cache-worker && npx wrangler deploy && cd ..        # deploy the cached worker first
cd front-door-worker && npx wrangler deploy && cd ..   # then the front door
```

### Test your own deployment

```sh
FDW=https://front-door-worker.<your-subdomain>.workers.dev ./demo.sh
```

Or run the raw curls manually:

```sh
URL="https://front-door-worker.<your-subdomain>.workers.dev/products/widget"
curl -sD - -o /dev/null "$URL" | grep -iE 'cf-cache-status|x-run-id'
curl -sD - -o /dev/null "$URL" | grep -iE 'cf-cache-status|x-run-id'
```

To inspect the R2 object stored under the same canonical key:

```sh
npx wrangler r2 object get cache-worker-snapshots/en/products/widget --remote
```

## How the key works

The front-door worker rewrites the request path to a canonical form
(`/{lang}{path}`) and forwards it over the service binding. Workers Cache keys
on that path, and the cache-worker uses the same path as its R2 object key.
The key is defined once, in the front-door worker, so the cache and R2 cannot
drift.
