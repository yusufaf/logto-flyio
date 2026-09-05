# Tailscale's own image + socat. socat is the workaround for Tailscale Serve
# only proxying to 127.0.0.1 (https://tailscale.com/kb/1242/tailscale-serve)
# — it forwards Serve's local port over to logto-af's private 6PN address,
# which Serve can't reach directly.
#
# Before relying on this: try dropping socat/this Dockerfile entirely and
# pointing serve.json's Proxy straight at http://logto-af.internal:3002 with
# the stock `tailscale/tailscale` image — TS_SERVE_CONFIG writes the serve
# config directly and may not enforce the CLI's localhost-only check. If
# that works, it's simpler; if not, this is the fallback.
FROM tailscale/tailscale:stable

RUN apk add --no-cache socat

COPY serve.json /config/serve.json
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

ENTRYPOINT ["/app/start.sh"]
