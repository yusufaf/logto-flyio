# Working in this repo

**This repo is public.** Before committing, check whether a value reveals
private infrastructure rather than just naming a public one:

- Fine to commit: Fly app names, `*.fly.dev` hostnames, the real custom
  domain (`auth.yusufaf.dev`) — these are already public the moment the app
  is deployed or DNS exists.
- NOT fine to commit: anything that only has meaning to someone already on
  private infra — a Tailscale tailnet's `ts.net` hostname (reveals the
  opaque tailnet ID), a WireGuard peer address, an internal-only API key or
  webhook URL, etc. Treat these like `DB_URL`/`SECRET_VAULT_KEK`: set via
  `fly secrets set`, referenced by name in `fly.toml`/README, never the
  literal value.

If you're about to write a real value into a committed file, ask: would this
line, on its own, tell an outside reader something about private network
topology they couldn't already get from the public deploy? If yes, it's a
secret — even if it's not a credential in the traditional sense.
