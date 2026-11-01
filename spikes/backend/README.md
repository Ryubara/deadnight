# Backend spike

Throwaway prototype for [the platform backend research](../../docs/research/platform-backend.md): Discord sign-in
(stubbed), lobbies, the hand-off to a game server, saves. Its code is not moved into the game as it is.

```sh
npm ci
npm test                       # 11 tests, no services needed
sh scripts/dev-compose.sh up --build -d   # Postgres + backend + stub game server, throwaway secrets
npm run e2e                    # two players sign in, share a lobby, connect to the game server
sh scripts/dev-compose.sh down -v
```

Configuration is environment variables only (`src/config.ts`); nothing has a secret default, and `DISCORD_MODE=stub`
is refused when `NODE_ENV=production`. Nothing here deploys or creates cloud resources.
