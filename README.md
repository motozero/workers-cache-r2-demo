# Workers Cache + R2: cache in front of a Worker

A small, self-contained demo of caching a Cloudflare Worker's output with
**Workers Cache**, so the Worker runs only on a cache miss, with a durable
**R2** tier behind it. One canonical key drives both the cache and the R2
object, so there is nothing to keep in sync.

## What it shows

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

## Prerequisites

- A Cloudflare account with Workers Cache available (`cache.enabled`) and R2 enabled.
- Wrangler 4.69.0 or newer.

## Deploy

```sh
npm install                                            # installs wrangler locally
npx wrangler r2 bucket create cache-worker-snapshots

cd cache-worker && npx wrangler deploy && cd ..        # deploy the cached worker first
cd front-door-worker && npx wrangler deploy && cd ..   # then the front door
```

## Test

Hit the front-door worker twice on the same path:

```sh
URL="https://front-door-worker.<your-subdomain>.workers.dev/products/widget"
curl -sD - -o /dev/null "$URL" | grep -iE 'cf-cache-status|x-run-id'
curl -sD - -o /dev/null "$URL" | grep -iE 'cf-cache-status|x-run-id'
```

Expected:

- First call: `cf-cache-status: MISS` and a fresh `x-run-id`.
- Second call: `cf-cache-status: HIT` and the **same** `x-run-id`.

The frozen `x-run-id` is the proof: on the hit, the cache served the response and
the worker did not execute. Use a new path for a fresh MISS then HIT.

## How the key works

The front-door worker rewrites the request path to a canonical form
(`/{lang}{path}`) and forwards it over the service binding. Workers Cache keys on
that path, and the cache-worker uses the same path as its R2 object key. The key
is defined once, in the front-door worker, so the cache and R2 cannot drift.

## Layout

- `front-door-worker/` - orchestrator, not cached, builds the canonical key.
- `cache-worker/` - `cache.enabled`, R2-bound, runs only on a miss. No public
  URL; reachable only via the service binding.
