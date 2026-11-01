#!/usr/bin/env sh
# Runs `docker compose` with throwaway secrets made for this run (nothing is written to disk).
# Usage: scripts/dev-compose.sh up --build   |   scripts/dev-compose.sh down -v
set -eu
secret() { node -e "console.log(require('node:crypto').randomBytes(32).toString('hex'))"; }
export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(secret)}"
export SESSION_SECRET="${SESSION_SECRET:-$(secret)}"
export TICKET_SECRET="${TICKET_SECRET:-$(secret)}"
export GAME_SERVER_SECRET="${GAME_SERVER_SECRET:-$(secret)}"
exec docker compose "$@"
