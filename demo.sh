#!/usr/bin/env bash
# demo.sh — Workers Cache in front of a Worker, proven in under a minute.
# No Cloudflare account required to run against the live reference deployment.
#
# Proves three things end-to-end:
#   1. Cold MISS. The cached worker ran. Fresh x-run-id.
#   2. Same URL: HIT with the SAME x-run-id (the worker did NOT execute).
#   3. A different path: fresh MISS with a different x-run-id (per-key isolation).
#
# The cached worker generates a new x-run-id every time it actually runs.
# If the same id comes back across calls, the worker did not run; Workers Cache
# served the response without invoking the worker. That is the proof.
#
# Each run uses a unique path (epoch in the URL) so step 1 is always a fresh
# MISS, regardless of how many times you've run this demo today.
#
# To run against your own deployment instead of the reference one:
#   FDW=https://front-door-worker.<your-subdomain>.workers.dev ./demo.sh

set -euo pipefail

: "${FDW:=https://front-door-worker.laboratory.workers.dev}"

EPOCH=$(date +%s)
DEMO_PATH="/demo-$EPOCH"
URL="$FDW$DEMO_PATH"

bold() { printf "\n\033[1m%s\033[0m\n" "$*"; }
dim()  { printf "\033[2m%s\033[0m\n" "$*"; }
hdrs() { grep -iE '^(cf-cache-status|x-run-id|x-source|x-cache-key):' | sed 's/^/   /'; }

bold "The claim"
dim "Workers Cache fronts the cached worker. On a HIT the worker does NOT execute."
dim "The cached worker mints a new x-run-id every time it actually runs."
dim "If the same id comes back across calls, the worker did not run."
echo
dim "Target: $FDW"

bold "Step 1. Cold path, first call. Expect MISS."
echo "+ curl $URL"
curl -sD - -o /tmp/cw_body1 "$URL" | hdrs
echo "   body: $(cat /tmp/cw_body1)"
dim "cf-cache-status: MISS, fresh x-run-id, x-source: origin (R2 was empty, the"
dim "worker generated a snapshot and stored it)."

sleep 1

bold "Step 2. Same URL. Expect HIT with the SAME x-run-id."
echo "+ curl $URL"
curl -sD - -o /tmp/cw_body2 "$URL" | hdrs
dim "Same x-run-id as Step 1 means the worker did not execute on this hit."
dim "Cloudflare served the cached response directly."

bold "Step 3. Sanity check: response bodies are byte-identical."
if diff -q /tmp/cw_body1 /tmp/cw_body2 >/dev/null; then
  echo "   identical ✓"
else
  echo "   DIFFERENT — something is wrong"
fi
rm -f /tmp/cw_body1 /tmp/cw_body2

sleep 1

bold "Step 4. A different path. Expect fresh MISS with a different x-run-id."
URL2="$FDW/demo-different-$EPOCH"
echo "+ curl $URL2"
curl -sD - -o /dev/null "$URL2" | hdrs
dim "Different x-cache-key, different x-run-id. The cache is keyed, not catch-all."

bold "Done."
dim "What you just saw:"
dim "  - Workers Cache fronted the cached worker."
dim "  - On the repeat hit, the worker did not run (frozen x-run-id is the proof)."
dim "  - Each unique path is its own cache entry."
dim "  - The same canonical path string drives both Workers Cache and the R2 object"
dim "    key — see cache-worker/src/index.ts and front-door-worker/src/index.ts."
dim "  - Deploy your own copy (see README) to inspect the R2 object yourself."
