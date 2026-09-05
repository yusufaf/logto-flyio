#!/bin/sh
# socat bridges Serve's 127.0.0.1:3002 (all Serve can proxy to, see
# Dockerfile) over to logto-af's private 6PN address.
set -e

socat TCP4-LISTEN:3002,bind=127.0.0.1,fork,reuseaddr TCP6:logto-af.internal:3002 &
SOCAT_PID=$!

# `fork` keeps socat's listener up through per-connection failures, but if
# it dies outright (OOM, fatal error) there's otherwise no signal — Fly
# still sees a healthy container while the admin console silently can't be
# reached. Watch it and kill PID 1 (containerboot, via exec below) so the
# whole container exits and Fly restarts it.
( while kill -0 "$SOCAT_PID" 2>/dev/null; do sleep 5; done; echo "socat exited, restarting container"; kill 1 ) &

exec /usr/local/bin/containerboot
