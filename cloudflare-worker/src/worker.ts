/**
 * AnyEx installer + skill-distribution edge worker.
 *
 * Routes (all on the `install.anyex.ai` zone):
 *
 *   GET  /polymarket                  → serve install.sh as text/x-shellscript so
 *                                       `curl -fsSL ... | bash` works.
 *   GET  /polymarket/SKILL.md         → serve the skill manifest directly (useful
 *                                       for users who want to inspect before
 *                                       installing, or for partners building
 *                                       their own installers).
 *   GET  /polymarket/install.sh       → alias for /polymarket (some users will
 *                                       guess this path).
 *   GET  /healthz                     → liveness probe.
 *   GET  /                            → 302 to https://polymarket.anyex.ai.
 *
 * Everything else 404s. The worker is a thin edge cache around the GitHub raw
 * URLs — no auth, no rate-limiting beyond Cloudflare's default DDoS protection.
 *
 * Source of truth: github.com/Meowster-s-Kitchen/anyex-skills/main
 */

interface Env {
  /**
   * Optional override for the upstream repo raw base. Defaults to the prod
   * `Meowster-s-Kitchen/anyex-skills/main`. Useful for staging via
   * `wrangler dev --var REPO_RAW=https://raw.githubusercontent.com/.../staging`.
   */
  REPO_RAW?: string
}

const DEFAULT_REPO_RAW =
  'https://raw.githubusercontent.com/Meowster-s-Kitchen/anyex-skills/main'

const LANDING_URL = 'https://polymarket.anyex.ai'

const SKILL_DIR_NAME = 'Anyex-prediction-market-delegate-with-KiteAI'

/**
 * Bumped on every `wrangler deploy` to bust the upstream cache deterministically
 * without dashboard-side purges. Just increment when shipping changes that need
 * to propagate faster than the configured TTL.
 */
const WORKER_VERSION = '2'

/**
 * Map a request path to the upstream file path on GitHub raw.
 * Returns null when the path is unmapped (will 404).
 */
function resolveUpstream(pathname: string): {
  upstreamPath: string
  contentType: string
} | null {
  const p = pathname.replace(/\/+$/, '') // strip trailing slash

  // Install script — primary entry point. `/polymarket` and `/polymarket/install.sh`
  // both serve install.sh, content-type as shell script so curl|bash works.
  if (p === '/polymarket' || p === '/polymarket/install.sh') {
    return {
      upstreamPath: '/install.sh',
      contentType: 'text/x-shellscript; charset=utf-8',
    }
  }

  // Direct skill manifest download.
  if (p === '/polymarket/SKILL.md') {
    return {
      upstreamPath: `/${SKILL_DIR_NAME}/SKILL.md`,
      contentType: 'text/markdown; charset=utf-8',
    }
  }

  return null
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url)

    // Only GET / HEAD.
    if (req.method !== 'GET' && req.method !== 'HEAD') {
      return new Response('Method Not Allowed', {
        status: 405,
        headers: { Allow: 'GET, HEAD' },
      })
    }

    // Liveness probe.
    if (url.pathname === '/healthz') {
      return new Response('ok', {
        headers: { 'content-type': 'text/plain; charset=utf-8' },
      })
    }

    // Root → bounce to landing.
    if (url.pathname === '/' || url.pathname === '') {
      return Response.redirect(LANDING_URL, 302)
    }

    const resolved = resolveUpstream(url.pathname)
    if (!resolved) {
      return new Response(
        `Not found.\n\nTry:\n  curl -fsSL ${url.origin}/polymarket | bash\n  ${LANDING_URL}\n`,
        { status: 404, headers: { 'content-type': 'text/plain; charset=utf-8' } },
      )
    }

    const upstreamBase = env.REPO_RAW ?? DEFAULT_REPO_RAW
    // Cache-buster: ties the edge cache key to this worker's deployed code.
    // Every `wrangler deploy` ships a new `WORKER_VERSION` constant below,
    // which gives us a fresh cache key without manual purges. GitHub raw
    // ignores extra query strings, so this is a no-op on the upstream side.
    const upstreamUrl = `${upstreamBase}${resolved.upstreamPath}?v=${WORKER_VERSION}`

    // Pass through. Edge-cache lightly — install.sh + SKILL.md change rarely
    // but when they DO change we want propagation in tens of seconds, not
    // minutes. cf.cacheTtlByStatus lets us cache 200s for a minute while
    // bypassing cache on 4xx/5xx upstream errors.
    const upstream = await fetch(upstreamUrl, {
      cf: {
        cacheEverything: true,
        cacheTtlByStatus: {
          '200-299': 60,
          '404': 5,
          '500-599': 0,
        },
      },
    })

    if (!upstream.ok) {
      return new Response(
        `Failed to fetch ${upstreamUrl} (HTTP ${upstream.status}).\n` +
          `If this persists, report at https://github.com/Meowster-s-Kitchen/anyex-skills/issues\n`,
        { status: 502, headers: { 'content-type': 'text/plain; charset=utf-8' } },
      )
    }

    const body = await upstream.text()

    return new Response(body, {
      status: 200,
      headers: {
        'content-type': resolved.contentType,
        'cache-control': 'public, max-age=60, s-maxage=60',
        'x-served-by': 'install.anyex.ai',
        'access-control-allow-origin': '*',
      },
    })
  },
}
