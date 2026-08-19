# Logto on Fly.io

Fly.io deployment config for [Logto](https://github.com/logto-io/logto)
(self-hosted OSS), the identity provider for `auth.yusufaf.dev` — one shared
user directory across `quizaroni`, `nba-central`, and (later) other apps, with
per-project organizations. See the migration plan this repo is Phase 1 of for
the full picture.

Two Fly apps:

| Fly app | image | exposure |
|---|---|---|
| `logto-af` | `svhd/logto:latest` (official) | **public** HTTPS, always-on |
| `logto-db` | `postgres:17-alpine` | **private** (6PN only), always-on |

Logto is stateless — all persistence is in Postgres, so unlike
[`wallabag-flyio`](https://github.com/yusufaf/wallabag-flyio) this needs no
custom Dockerfile. Postgres is a second self-hosted Fly app rather than Fly
Managed Postgres (`fly mpg`) — its cheapest plan is **$38/mo**, versus ~$2/mo
for a small VM + volume here — following the same two-app pattern as
[`sparkyfitness-flyio`](https://github.com/yusufaf/sparkyfitness-flyio)'s
`db` app.

## ⚠️ Choose your own app names first

**Fly.io app names are globally unique** (shared across all Fly users). The
names committed here are `logto-af` and `logto-db` — pick your own if taken.
If you rename either, update it in **both** places:

| What | Where |
|---|---|
| `logto-af` app name | `fly.toml` → `app`, and `ENDPOINT` if you're not using a custom domain |
| `logto-db` app name | `logto-db/fly.toml` → `app`, and `DB_URL` (see step 4) |

## Prerequisites
- [`fly` CLI](https://fly.io/docs/flyctl/install/) installed and `fly auth login` done
- `openssl` (for generating secrets)

## Cost (rough, LAX region, shared-cpu-1x)

```
logto-af   (1024mb, always-on, min_machines_running=1)   ≈ $5.70/mo
logto-db   (256mb,  always-on)                           ≈ $1.94/mo
logto-db volume (1GB)                                     ≈ $0.15/mo
                                                          ──────────
                                                            ~$7.80/mo
```

Auto-stop for `logto-af` is deliberately **not** used — a cold start on the
JWKS endpoint (`/oidc/jwks`) can make a Lambda API authorizer time out rather
than just feel slow. This is the first always-on thing in this account; every
other Fly app here suspends when idle.

## Deploy

### 1. Create the database app + volume
```bash
fly apps create logto-db          # use your own name; see above
fly volumes create logto_pgdata --app logto-db --region lax --size 1
```

### 2. Database secrets + deploy
```bash
fly secrets set --app logto-db \
  POSTGRES_USER=logto \
  POSTGRES_PASSWORD="$(openssl rand -hex 24)" \
  POSTGRES_DB=logto
fly deploy --app logto-db --config logto-db/fly.toml
```

### 3. Create the app + Postgres database + role
Postgres needs a `logto` database created before Logto's own migrations run
against it (the `postgres:17-alpine` image only auto-creates the DB named by
`POSTGRES_DB`, which step 2 already set to `logto` — so this step is usually a
no-op; skip straight to step 4 unless `\l` inside `fly pg connect` shows no
`logto` database).

### 4. App secrets
```bash
fly apps create logto-af          # use your own name; see above

# DB_URL: <user>:<password> must match POSTGRES_USER/POSTGRES_PASSWORD from
# step 2. logto-db.internal is Fly's private DNS for the logto-db app — only
# reachable from other apps in this org, never from the public internet.
fly secrets set --app logto-af \
  DB_URL="postgres://logto:<password-from-step-2>@logto-db.internal:5432/logto"

# SECRET_VAULT_KEK: base64-encoded AES-256 key encryption key.
fly secrets set --app logto-af \
  SECRET_VAULT_KEK="$(openssl rand -base64 32)"
```

### 5. Deploy + seed
```bash
fly deploy --app logto-af
fly ssh console --app logto-af -C "npm run cli db seed -- --swe"
fly logs --app logto-af
```

## Custom domain (`auth.yusufaf.dev`)

Do this **after** step 5 confirms the app boots on `https://logto-af.fly.dev`
(see Verify below) — don't create the DNS record until the Fly app is
actually running (dangling-record risk, see the migration plan's Security
section).

```bash
fly certs add auth.yusufaf.dev --app logto-af
```
Fly prints the A/AAAA records to add — same flow as `tf2.yusufaf.dev`. Add
them at Porkbun, then poll:
```bash
fly certs show auth.yusufaf.dev --app logto-af   # wait for "Ready"
```
Once Ready, flip `fly.toml`'s `ENDPOINT` to `https://auth.yusufaf.dev`,
commit, and redeploy. `ADMIN_ENDPOINT` stays `http://localhost:3002` — the
admin console is never exposed on the custom domain either (see below).

## Admin console access

**Deliberately not published.** Port 3002 (the Admin Console) is never in
`fly.toml`'s `[http_service]` — it has no public listener at all. This is the
mitigation for the highest-value target in the whole identity system. Reach
it with:
```bash
fly proxy 3002:3002 -a logto-af
```
then open `http://localhost:3002` in a browser. First run walks through
creating the admin account (this is Logto's own account system — nothing to
do with `auth.yusufaf.dev`'s eventual end-user accounts).

## Verify

```bash
curl -s https://logto-af.fly.dev/oidc/.well-known/openid-configuration | jq .issuer
# -> "https://logto-af.fly.dev/oidc"  (or https://auth.yusufaf.dev/oidc post-cutover)

fly proxy 3002:3002 -a logto-af   # console reachable, can create an org
```
Then, in the console: create one throwaway SPA application and confirm a
sign-in redirect completes end to end (Get Started flow walks through this).

## Ongoing
```bash
fly logs --app logto-af              # tail logs
fly status --app logto-af            # machine status
fly ssh console --app logto-af       # shell in
fly deploy --app logto-af            # redeploy after a config or version change
```

## Notes / gotchas

- **Postgres backups are non-optional.** Losing `logto-db`'s volume loses
  every account across every project this IdP serves. A Fly volume is not a
  backup — schedule a real `pg_dump` off-box
  (`fly ssh console --app logto-db -C "pg_dump -U logto logto"` piped
  somewhere durable, on a cron).
- **Logto CVEs are your problem now.** Watch the
  [release feed](https://github.com/logto-io/logto/releases); plan on
  redeploying `logto-af` for security releases (`fly deploy` re-pulls
  `svhd/logto:latest` unless you pin a tag).
- **Availability is shared.** `logto-af` down = every app's login down —
  accepted deliberately (hence always-on, not auto-stop).
- **Never scope any cookie to `.yusufaf.dev`.** Logto's session cookie is
  host-only on `auth.yusufaf.dev` by default — don't "fix" this. See the
  migration plan's Security section for why.
- **One API resource per project** in the Logto console, so each app's
  access token carries a distinct `aud` — a token from one project's API
  resource must be rejected by another project's authorizer.
