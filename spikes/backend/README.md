# Backend spike

Throwaway prototype for [the platform backend research](../../docs/research/platform-backend.md): Discord sign-in
(stubbed), lobbies, the hand-off to a game server, saves. Its code is not moved into the game as it is.

```sh
npm ci
npm test                       # no services needed
sh scripts/dev-compose.sh up --build -d   # Postgres + backend + stub game server, throwaway secrets
npm run e2e                    # two players sign in, share a lobby, connect to the game server
sh scripts/dev-compose.sh down -v
```

Configuration is environment variables only (`src/config.ts`) and fails closed: it refuses to start on anything unsafe
or unclear. Nothing has a secret default; `DISCORD_MODE` has no default (`live` or `stub`); `stub` also needs
`ALLOW_STUB_SIGN_IN=1` and is refused when `NODE_ENV=production`; `PORT` must be an integer from 1 to 65535; the
session, ticket and game-server secrets must differ. Stub users are stored as `stub:<id>`, so they cannot collide
with real Discord ids. Nothing here deploys or creates cloud resources.
