# Backend spike

Throwaway prototype for [the platform backend research](../../docs/research/platform-backend.md): Discord sign-in
(stubbed), lobbies, the hand-off to a game server, saves. Its code is not moved into the game as it is.

```sh
npm ci
npm test                       # no services needed
TEST_DATABASE_URL=postgres://... npm test   # also runs the Postgres store tests (a throwaway database)
sh scripts/dev-compose.sh up --build -d   # Postgres + backend + stub game server
npm run e2e                    # two players sign in, share a lobby, connect to the game server
sh scripts/dev-compose.sh down -v         # wipes the database and the secrets
```

`dev-compose.sh` makes the development secrets once and keeps them in the workspace `scratch/deadnight-backend-dev/`
folder (or in `DEV_SECRETS_FILE`), so they match the database volume for as long as the stack exists. To keep your data:

- Restart the backend: `sh scripts/dev-compose.sh restart backend` (or `stop` then `start`).
- Run `up -d` again, or `down` then `up -d`: the same secrets and the same volume are used, nothing is lost.
- Start over: `down -v` deletes the volume and the secrets together.
- If the volume is there but the secrets file is gone, the script stops and says so; run `down -v`.

Host ports are `BACKEND_PORT` (default 3000) and `GAMESERVER_PORT` (default 8080); `npm run e2e` reads `BACKEND_URL`.

Configuration is environment variables only (`src/config.ts`) and fails closed: it refuses to start on anything unsafe
or unclear. Nothing has a secret default; `DISCORD_MODE` has no default (`live` or `stub`); `stub` also needs
`ALLOW_STUB_SIGN_IN=1` and is refused when `NODE_ENV=production`; `PORT` must be an integer from 1 to 65535; the
session, ticket and game-server secrets must differ. Stub users are stored as `stub:<id>`, so they cannot collide
with real Discord ids. Nothing here deploys or creates cloud resources.
