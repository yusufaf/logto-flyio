#!/bin/sh
# socat bridges Serve's 127.0.0.1:3002 (all Serve can proxy to, see
# Dockerfile) over to logto-af's private 6PN address. Backgrounded so
# containerboot (tailscaled + the actual `tailscale up`/serve apply) can take
# over as PID 1 via exec below.
set -e

socat TCP4-LISTEN:3002,bind=127.0.0.1,fork,reuseaddr TCP6:logto-af.internal:3002 &

exec /usr/local/bin/containerboot
