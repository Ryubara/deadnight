#!/usr/bin/env sh
# Runs `docker compose` with development secrets that stay the same for the life of the stack.
#
# The secrets are made once and kept in a file outside the repository (the workspace `scratch/` folder), so a second
# `up` finds the same Postgres password the database volume was created with. `down -v` removes the volume and the
# file together. If the volume exists but the file is gone, this refuses to start instead of letting the backend
# crash with `auth_failed`.
#
# Usage: sh scripts/dev-compose.sh up --build -d   |   restart backend   |   down        (keeps data and secrets)
#        sh scripts/dev-compose.sh down -v                                              (wipes both)
# Variables: DEV_SECRETS_FILE (where the secrets live), or set any secret yourself (then it is yours to keep stable).
set -eu

here=$(cd "$(dirname "$0")" && pwd)
volume="deadnight-backend-dev_pgdata"
names="POSTGRES_PASSWORD SESSION_SECRET TICKET_SECRET GAME_SERVER_SECRET"

# The subcommand is the first word that is not an option; -v / --volumes asks `down` to delete the volume.
command_word=""
volumes=0
for arg in "$@"; do
  case "$arg" in
    -v | --volumes) volumes=1 ;;
    -*) ;;
    *) [ -n "$command_word" ] || command_word=$arg ;;
  esac
done

workspace_secrets_file() {
  dir=$here
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    if [ -d "$dir/scratch" ] && [ -d "$dir/repos" ]; then
      echo "$dir/scratch/deadnight-backend-dev/secrets.env"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

if [ -n "${DEV_SECRETS_FILE:-}" ]; then
  file=$DEV_SECRETS_FILE
elif ! file=$(workspace_secrets_file); then
  echo "dev-compose: no workspace scratch/ folder found above $here; set DEV_SECRETS_FILE to a path outside the repository." >&2
  exit 2
fi

secret() { node -e "console.log(require('node:crypto').randomBytes(32).toString('hex'))"; }

if [ "$command_word" = "down" ]; then
  # Taking the stack down only needs the variables to exist, not to be right.
  for name in $names; do
    eval "[ -n \"\${$name:-}\" ] || export $name=unused"
  done
else
  mkdir -p "$(dirname "$file")"
  for name in $names; do
    eval "current=\${$name:-}"
    [ -z "$current" ] || continue
    value=$(grep "^$name=" "$file" 2>/dev/null | head -n 1 | cut -d= -f2-) || value=""
    if [ -z "$value" ]; then
      if [ "$name" = "POSTGRES_PASSWORD" ] && docker volume inspect "$volume" > /dev/null 2>&1; then
        echo "dev-compose: the database volume '$volume' exists but its password is not in $file." >&2
        echo "dev-compose: run 'sh scripts/dev-compose.sh down -v' to delete the development database, or restore the file." >&2
        exit 1
      fi
      value=$(secret)
      (umask 077 && echo "$name=$value" >> "$file")
    fi
    export "$name=$value"
  done
fi

status=0
docker compose "$@" || status=$?
if [ "$status" -eq 0 ] && [ "$command_word" = "down" ] && [ "$volumes" -eq 1 ]; then
  rm -f "$file"
  echo "dev-compose: removed the development secrets with the volume ($file)"
fi
exit "$status"
