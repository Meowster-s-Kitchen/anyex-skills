# anyex-installer (Cloudflare Worker)

Edge worker that serves the `curl | bash` install URL and exposes the skill manifest at a stable HTTPS endpoint.

## Routes

| URL | Behavior |
|---|---|
| `GET install.anyex.ai/polymarket` | Serves `install.sh` from the parent repo with `Content-Type: text/x-shellscript`. Designed for `curl -fsSL ... \| bash`. |
| `GET install.anyex.ai/polymarket/install.sh` | Alias for `/polymarket`. |
| `GET install.anyex.ai/polymarket/SKILL.md` | Serves the skill manifest as `text/markdown`. |
| `GET install.anyex.ai/healthz` | Liveness probe. Returns `200 ok`. |
| `GET install.anyex.ai/` | `302` to `https://polymarket.anyex.ai`. |

All upstream content is fetched from `https://raw.githubusercontent.com/Meowster-s-Kitchen/anyex-skills/main`. Override with the `REPO_RAW` env var for staging.

## Deploy

One-time:

1. The Cloudflare zone `anyex.ai` must already exist. If not, add it in the Cloudflare dashboard and update your domain registrar's nameservers.
2. Add a DNS record (the worker will own the route):
   - Type: `AAAA`, Name: `install`, Target: `100::`, Proxy: **on** (orange cloud).
   *(The address is a placeholder — Cloudflare routes the worker regardless. An A record to `192.0.2.1` works equivalently.)*
3. `wrangler login` (or set `CLOUDFLARE_API_TOKEN` in CI).

Then from this directory:

```bash
pnpm install            # or npm install
pnpm deploy             # or wrangler deploy
```

After deploy, sanity-check:

```bash
curl -sI https://install.anyex.ai/polymarket | head -5
curl -fsSL https://install.anyex.ai/polymarket | head -30
```

Live request log:

```bash
pnpm tail
```

## Local dev

```bash
pnpm dev               # wrangler dev — http://localhost:8787
curl -fsSL http://localhost:8787/polymarket | head -10
```

## Rolling back

```bash
wrangler deployments list
wrangler rollback <deployment-id>
```

## CI deployment (optional)

Add `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` as repo secrets, then GitHub Actions can run `wrangler deploy` on push to `main`. See [Cloudflare's Workers CI docs](https://developers.cloudflare.com/workers/wrangler/ci-cd/) for the workflow template.
