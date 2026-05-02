# `/api/workflows` auth bug — reproduction

Verified live on 2026-05-02 against `app.keeperhub.com`.

## Claim

`GET /api/workflows` returns **HTTP 200 with body `[]`** regardless of authentication. Specifically: a valid `wfb_` key, a fabricated `kh_obviouslyfakekey`, an empty bearer, and *no `Authorization` header at all* all produce the same response.

This contradicts the published [Authentication](https://docs.keeperhub.com/api/authentication) doc, which states `wfb_` keys are "Webhook triggers" only and `/api/workflows` is organization-scoped. Unauthenticated and wrong-scope requests should return 401.

## Reproduction

```bash
# 1. Valid wfb_ key
curl -i "https://app.keeperhub.com/api/workflows" \
  -H "Authorization: Bearer wfb_REDACTED"
# → HTTP/2 200, body: []

# 2. Obviously fake key
curl -i "https://app.keeperhub.com/api/workflows" \
  -H "Authorization: Bearer kh_obviouslyfakekey"
# → HTTP/2 200, body: []

# 3. No Authorization header
curl -i "https://app.keeperhub.com/api/workflows"
# → HTTP/2 200, body: []

# 4. Empty bearer
curl -i "https://app.keeperhub.com/api/workflows" \
  -H "Authorization: Bearer "
# → HTTP/2 200, body: []
```

For comparison, `/api/integrations` correctly rejects no-auth:

```bash
curl -i "https://app.keeperhub.com/api/integrations"
# → HTTP/2 401, body: {"error":"Unauthorized"}
```

## Why it matters

A new builder mistypes their API key, sees a 200 with `[]`, and concludes their organization has no workflows. They start creating, get more silent successes, and never discover the request was unauthenticated until something later breaks in a confusing way.

The contract the rest of the API follows is "401 on missing/invalid auth." `/api/workflows` is the only org-scoped endpoint we tested that does not honor it.

## Suggested fix

The handler should reject unauthenticated requests with `401 {"error":"Unauthorized"}` before falling through to the org scope filter. If the silent-empty behavior is intentional (e.g., to avoid leaking that the endpoint exists), document it explicitly — silent acceptance of any auth string is worse than an explicit 401.

## Related observations

- Documented endpoints `/api/executions` and `/api/execute` both return Next.js HTML 404 with a `wfb_` key. They should at minimum return JSON 401 (rejected scope). The HTML 404 suggests the routes are not mounted at the documented paths.
- Error envelope on the wire is `{"error": "<string>"}`, not the documented `{"error": {"code": "...", "message": "..."}}`. Agents switching on `response.error.code` always hit the default branch.
- No `X-RateLimit-*` or `Retry-After` headers observed across 21+ rapid requests. The documented 100 req/min limit is unobservable from the client side.
