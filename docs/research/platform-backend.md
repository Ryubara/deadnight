# Platform backend

Deadnight has two server layers (maintainer decision, issue #25). The **game server** is headless Godot running the
same simulation as the client. The **platform backend** is everything else: Discord sign-in, lobbies and matchmaking,
telling a player which game server to connect to, saved progress. This page compares three ways to build the
backend, recommends one, and describes the prototype in `spikes/backend/`. The game server itself and its protocol are
in the multiplayer research page (issue #6, not landed when this was written).

## Recommendation

**Build it ourselves in TypeScript on Node (Fastify) with Postgres.** The surface we need is small (sign-in, lobbies,
one handoff call, saves: about 900 lines including the Discord client, with tests), the one hard part is starting or
choosing a headless Godot server, and neither Nakama nor Colyseus does that on Railway for us. What both frameworks
are best at (realtime state, authoritative matches) is what we explicitly keep in Godot. Revisit if we need friends,
parties, chat, leaderboards or tournaments: that is Nakama's territory, and the small API surface keeps the swap
cheap.

## Comparison

| | Custom TypeScript/Node | Nakama | Colyseus |
| --- | --- | --- | --- |
| **What it gives** | Only what we write. Spike: sign-in, lobbies, handoff, versioned saves, health, logs. | Accounts and sessions, storage, matchmaker, parties, chat, leaderboards, console, runtime hooks and RPCs. | Rooms with filtering and queueing, delta-compressed state sync, reconnection, presence, load-balancer and Redis scaling. |
| **Discord sign-in** | One route: the Activity sends the `authorize()` code, the backend swaps it at `oauth2/token` and reads `users/@me`. Written and tested (live client with a stubbed `fetch`). | Not built in; the docs say to validate the provider token yourself in a before hook on custom authentication. Needs our code in its runtime. | Official Discord Activity template and guide; the server reads `DISCORD_CLIENT_ID` and `DISCORD_CLIENT_SECRET`. Identity inside a room comes from `onAuth`. |
| **Handing a player a game server** | Our code: a registry of game servers (heartbeats), `allocate()`, a 60 s HMAC ticket. Built and tested. | Nothing for Railway. The docs list fleet guides for GameLift, Edgegap and i3D.net only. We would write the allocation as an RPC or matchmaker hook. | A room is the match and runs the simulation in Node, which is the layer we keep in Godot. We would use a room only as a lobby and still write the allocation. |
| **Runs on Railway** | Two services (backend, Postgres) plus the game servers. Plain `Dockerfile`, `PORT`, `/health`. | Official image plus Postgres; a community Railway template exists (3.41.0 with Postgres). Three ports (7349 to 7351); migrations before each start. | One Node service. Community guides only; room state is per process, so one replica until Redis is added. Colyseus Cloud (from $15 a month) is a different host. |
| **Idle cost on Railway** | Measured: backend 35 MiB, Postgres 33 MiB. | Measured: Nakama 13 MiB, Postgres 35 MiB, image 225 MB. | Not measured; a Node process, like the backend. |
| **Licence** | Ours (Fastify MIT, `ws` MIT, `pg` MIT). | Apache-2.0. | MIT. |
| **Extending it** | TypeScript with the full npm ecosystem. | TypeScript compiled to ES5 on the goja VM; no Node or browser APIs and no packages that need them; Go plugins as the escape hatch. | TypeScript on Node. |
| **What we own** | All the code and the schema; also all the upkeep. | Our hooks and RPCs; Nakama owns the data model and upgrades. | Our rooms; Colyseus owns the room lifecycle and wire format. |
| **Main risk** | We build and maintain every feature we add later. | Two runtimes and a second language model to learn for a small amount of logic. | A framework whose centre (rooms with state) is the part we do not use. |

All three cost the same order of magnitude on Railway: at $10 per GB of RAM a month and $20 per vCPU a month
([pricing](https://docs.railway.com/reference/pricing/plans)) a 35 MiB service is cents, and the $5 Hobby plan includes
$5 of usage. Cost does not decide this; the game servers will dominate the bill.

## What the prototype does

`spikes/backend/` (Fastify 5, Node 24, Postgres, `ws`; TypeScript run with Node's type stripping, built by `tsc` for the
image):

- `POST /auth/discord {code}` signs a user in. `DISCORD_MODE` has no default: `live` does the real exchange (Discord
  calls time out after 5 s: a stalled or failing Discord answers 502 `discord_unavailable`, a rejected code 401);
  `stub` accepts `stub:<id>:<name>`, stores the user as `stub:<id>` in `discord_id`, needs `ALLOW_STUB_SIGN_IN=1` and
  is refused when `NODE_ENV=production`. Returns a one-hour session token and the Discord
  `access_token` (the Embedded App SDK needs it for `authenticate()`).
- `POST /lobbies` creates a lobby (or joins the open one of the same Activity `instanceId`),
  `POST /lobbies/join-by-code`, `GET /lobbies/:id`, `POST /lobbies/:id/leave`, `POST /lobbies/:id/start` (host only;
  allocates a game server). A user is in at most one open lobby (409 `already_in_lobby`).
- `POST /lobbies/:id/ticket` returns `{address: {url, activityPath}, ticket}` for the caller's seat. The ticket names
  the game server it is for (`serverId`) and has a unique id (`jti`); see [the ticket](#the-game-server-ticket).
- `PUT/GET /saves/:slot`: a save is `{revision, schemaVersion, data}`; a stale `revision` is a 409 instead of lost
  progress. Format rules: [Save format](#save-format).
- `POST /internal/servers/heartbeat` (shared secret): a game server announces itself, its capacity and the ids of the
  matches it is running. `POST /internal/matches/:id/end` (shared secret): a match is over, its slot is free.
  How lobbies and capacity end: [Lobby and match lifecycle](#lobby-and-match-lifecycle).
- `src/stub-gameserver.ts` stands in for headless Godot: it heartbeats, and admits only a valid ticket
  that is unexpired, for this server and unused (`jti`), sent as the first WebSocket message.
- Configuration only from environment variables; JSON logs that never include headers or bodies (redaction of the
  code and tokens is configured as a backstop); `/health` and `/ready` (checks the database); graceful shutdown on
  `SIGTERM`.

Run it: `npm ci && npm test` in `spikes/backend/` (sign-in, lobbies, handoff, forged and expired tickets, capacity,
saves, config that fails closed, the live Discord client and its timeout). `scripts/dev-compose.sh up --build -d`
starts Postgres, the backend and the stub game server with development secrets kept in the workspace `scratch/` folder
for the life of the stack (a second `up`, `restart` and `down` keep the data, `down -v` wipes both), then `npm run e2e`
has two players sign in, share a lobby, start it and connect to the game server. Measured on the compose stack: the e2e
run passed, a save survived a backend restart (Postgres), and `docker compose stop` took 0.7 s because the process
closes on `SIGTERM`.

## Join flow: from the Activity to a running match

The Activity opens on the main menu, like every platform (#495). The sign-in runs in the background from the menu
(`ActivityRoom`, started by `main.gd` when the page has `instance_id`), together with a read of what the voice channel's
lobby is (`POST /lobbies/preview {instanceId}`); Play together then goes straight to the channel's lobby
([the lobby](../design/lobby.md)): the first player there makes it and hosts, the others read it (waiting, or a night in
progress and its round) and press Join. Nothing joins a lobby before a player opens that screen, so people who only
opened the Activity hold no seat. If the room could not be made ready the screen says why and tries again on the next
visit.

```mermaid
sequenceDiagram
    autonumber
    participant A as Activity (Godot web build)
    participant D as Discord client
    participant B as Backend
    participant P as Postgres
    participant X as Discord API
    participant G as Game server (headless Godot)

    G->>B: heartbeat every 5 s (url, activityPath, capacity, matchIds)
    A->>D: sdk.ready()
    A->>D: sdk.commands.authorize(client_id, code, identify)
    D-->>A: authorization code
    A->>B: POST /auth/discord {code} (through the Activity proxy)
    B->>X: POST oauth2/token (client secret stays here)
    X-->>B: access_token
    B->>X: GET users/@me
    X-->>B: id, username
    B->>P: upsert user
    B-->>A: session token + access_token
    A->>D: sdk.commands.authenticate(access_token)
    A->>B: POST /lobbies {instanceId} (friends in the same Activity land in one lobby)
    B-->>A: lobby
    Note over A,B: the other players do the same; every member polls GET /lobbies/:id (it is also their presence)
    A->>B: POST /lobbies/:id/start (host)
    B->>B: allocate the least loaded live game server
    B-->>A: lobby started, matchId
    A->>B: POST /lobbies/:id/ticket (every player)
    B-->>A: address {url, activityPath} + 60 s HMAC ticket
    A->>G: WebSocket wss://client_id.discordsays.com/activityPath (no ticket in the URL)
    A->>G: first message {type: join, ticket}
    G->>G: verify signature, expiry, serverId = me, matchId, jti not seen before
    G-->>A: welcome, then the simulation ticks
```

## Rooms: the game and the backend together

Deployed on Railway in `gdstudio-net-test` (#391): the backend (`spikes/backend`, Postgres beside it) and the game
server (`deadnight-server`, headless Godot). What a player does is [Playing online today](testing-multiplayer.md#playing-online-today);
what happens underneath:

1. **Sign in.** The web build calls `POST /auth/guest`: a random user in its own `guest:` id namespace (never a Discord
   id), a name the player may choose or `Guest 1234`, limited to 30 sign-ins an hour from one address and 2000 in all.
   The backend runs `DISCORD_MODE=live` with guests switched on (`GUEST_SIGN_IN=1`); `DISCORD_MODE=off` is the same
   with no Discord at all. Browsers on another origin than the backend need it in `CORS_ORIGINS`; inside a Discord Activity
   everything goes through the proxy (`/api`, `/server`) and is same-origin.
2. **A night.** *Create a night* is `POST /lobbies`: a lobby that waits ([the lobby](#the-lobby-before-the-night)) until
   its host calls `POST /lobbies/:id/start`, which allocates the least loaded game server with room; the lobby keeps a
   short code. *Quick join* is `POST /lobbies/quick`: a public night with
   room (open or already started), else a new public one. *Join with the code* is `POST /lobbies/join-by-code`, and it
   works on a night that has already started (a started night takes newcomers while the game server says it has room:
   its heartbeat carries `players`, the count in each match); the screen reads the code with `POST /lobbies/preview`
   first. A Discord Activity sends its `instanceId`: the first to ask makes the lobby, the rest join it.
3. **The handoff.** `POST /lobbies/:id/ticket` returns the server's address and a 60 s HS256 ticket (match, server, a
   single-use `jti`). The client connects and puts the ticket in its first message (the hello, never the URL).
4. **One process, several nights.** The game server (`GameServer`) owns the listener and a `NightHost` for each match,
   each in a `SubViewport` of its own (its own physics and navigation), so one Godot process hosts several nights, and
   no Railway service is made for a room. The first ticket of a match builds its night (a second ticket of the same
   match waits for it), a hello with a resume token goes to the room that holds the seat, a ticket of the same user takes
   the old seat instead of making a second player, and a night whose players have all gone is freed and reported with
   `POST /internal/matches/:id/end`. `capacity` (rooms a process takes, `ROOM_CAPACITY`, 3) is what it reports in the
   heartbeat; a fourth match is refused `FULL` and the backend does not give it a ticket (`no_server`) once the
   heartbeats are full. The rooms of a process share one tick, so they are sized together from a measurement on Railway
   ([rooms in one process](crowd-budget.md#rooms-in-one-process-561)): `ROOM_CAPACITY` 3 and `ALIVE_BUDGET` 120 (the most
   alive in all the rooms together, each cut to its share; a room with a browser in it stands 40 whatever it says),
   and `MAX_ALIVE` for a cap on any one room.

Environment of the services (names only; the secrets are Railway variables, never in the repository):

| Service | Variables |
| --- | --- |
| `backend` | `SESSION_SECRET`, `TICKET_SECRET`, `GAME_SERVER_SECRET` (all different, 32+ characters), `DATABASE_URL` (the Postgres reference), `DISCORD_MODE`, `DISCORD_CLIENT_ID`, `DISCORD_CLIENT_SECRET`, `GUEST_SIGN_IN=1`, `CORS_ORIGINS` |
| `deadnight-server` | `BACKEND_URL`, `GAME_SERVER_SECRET` and `TICKET_SECRET` (references to the backend's), `PUBLIC_URL` (`wss://` its public domain), `ACTIVITY_PATH=/server`, `ROOM_CAPACITY` (3), `ALIVE_BUDGET` (120), optionally `MAX_ALIVE` |

A path variable set from Git Bash on Windows is rewritten (`/server` became `C:/Program Files/Git/server`): set them with
`MSYS_NO_PATHCONV=1` or from PowerShell.

**Cost** (Railway, Hobby plan, measured on these services idle): backend about 35 MiB, Postgres about 35 MiB and the game
server a Godot process of a few hundred MiB; at $10 per GB-month and $20 per vCPU-month that is roughly $3 to $6 a month
with nobody playing, and a busy night adds a fraction of a core for each room in play.

## Player names

One name per player, the same on every screen of a night (#485).

- **Where it comes from.** A web or desktop player with no saved name is asked on the first Play together ("Skip, call me
  Guest" is an answer too) and can change it under More in the menu; it is kept in the profile and sent to
  `POST /auth/guest`. In a Discord Activity the backend reads it from Discord: the player's nickname in the guild the
  Activity runs in (`guildId` in `POST /auth/discord`, read with the `guilds.members.read` scope), else the global name,
  else the username. If the player refuses the scope the bridge asks for `identify` alone and the name falls back; the
  sign-in never fails for a name.
- **Cleaning (`spikes/backend/src/names.ts`).** Letters, digits, spaces and a few marks only, spaces squeezed, at most
  24 characters, a basic profanity filter; what is left empty becomes `Guest NNNN`. The backend is the one place that
  does it: anyone can send anything.
- **In the night.** The ticket carries the name; see [Names in a night](../design/networking.md#names-in-a-night).

## Save format

A save is the envelope `{revision, schemaVersion, data}`. `PUT` needs all three; `GET` returns all three (404 when the
slot is empty). Both validate the slot (`[a-z0-9_-]`, 1 to 32 characters).

- **`revision`** is optimistic concurrency: write the revision you read (0 for a new slot), a stale one is 409
  `revision_conflict`. Atomic in both stores (`INSERT ... ON CONFLICT DO NOTHING`, `UPDATE ... WHERE revision`).
- **`schemaVersion`** says how to read `data`. The backend holds a closed list (`SAVE_SCHEMA_VERSIONS` in
  `src/saves.ts`, now `[1]`) and refuses any other with 422 `unsupported_schema_version` and the list it knows. It
  never looks inside `data` to migrate it: the game owns the layout. To change what a save contains: add version N+1 to
  the list and deploy the backend first (it then accepts both), then ship the game, which reads any version it knows,
  migrates in memory and writes back the newest with the revision it read. Drop an old version from the list only when
  no client writes it. Rows saved before versioning count as version 1.
- **`data`** is an object up to 64 KiB, opaque to the backend. **64-bit values never travel as JSON numbers.** A number
  in JSON becomes a double (`JSON.parse("18446744073709551557")` gives `18446744073709552000`), and Postgres `jsonb`
  read through Node does the same, so the backend refuses any integer of 2^53 or more with 422 `unsafe_integer` and the
  path (`/rng/state`) instead of rounding it. Send such a value as a decimal string, or send the whole snapshot as one
  opaque base64 string of `var_to_bytes` (the rules snapshot's `to_wire()` is exactly that, see
  [rounds](../design/rounds.md)). Strings come back unchanged, tested through the API and against Postgres. Floats
  below 2^53 and integers up to 2^53 - 1 are ordinary JSON numbers.

## The lobby before the night

Design: [the lobby](../design/lobby.md). *Create a night* is `POST /lobbies` alone: the lobby stays **open** until its
host calls `POST /lobbies/:id/start`, and every member polls `GET /lobbies/:id` meanwhile.

- **The view** (`GET /lobbies/:id`, members only) has `members` as `[{userId, name, seat, host, away}]` in the order people
  came (seats close up when someone leaves), `hostId`, `state` (`open` or `started`), `players` (the game server's count
  once started), `round` (the night's round, null until the game server has said one), `matchId` and the usual code.
- **Start is the host's only** (`403 not_host`; a second one is `409 already_started`; every server busy is
  `503 no_server` and the lobby stays open). Members get a ticket only after it (`409 not_started` before).
- **Host handover.** A host who leaves, or who is dropped, passes the role to the next seat. The last member out closes
  an open lobby.
- **Presence.** Each poll (and a create or a join) marks the member as seen. In an **open** lobby, a member not seen for
  `memberAwayMs` (60 s) is dropped as if they had left, host role and seats included, but only while someone else was seen
  inside that minute: a lobby whose members are all quiet (every tab in the background, which stops the game's frames
  and so its polls) is never emptied by this and expires after ten idle minutes as before. `away` in the view is a member
  not seen for 15 s. A dropped member who polls again gets `403 not_member` and is free to open or join another lobby.
- **The round.** The game server's heartbeat has an optional `rounds` (`{matchId: round}`, next to `players`; `GameServer`
  sends it from `NightHost.round_number()`, 0 before round 1); an older server that sends none leaves `round` null.
- **Looking before joining.** `POST /lobbies/preview {code}` (any signed-in user, a body so the code stays out of the
  request log) answers `{code, state, round, players, maxPlayers, full, hostName, names}` and joins nobody; an unknown
  code is `404 not_found`. A started night's `full` is the game server's count, the same test `join` applies.
- **Late joiners.** Joining a started lobby is unchanged (`join-by-code` while the game server says there is room), and
  the ticket is the same single-use one.

Why polling and not a pushed channel: [the lobby design](../design/lobby.md#poll-or-push).

## Lobby and match lifecycle

Nothing in memory grows without bound. Times are constants in `src/lobbies.ts` and `src/servers.ts`, and tests move an
injected clock.

| What | Ends when |
| --- | --- |
| Open lobby | Idle for 10 minutes (create, join, leave, start and a member's `GET` all count as activity), or its last member leaves. A member not seen for a minute is dropped while another is still there ([presence](#the-lobby-before-the-night)). |
| Started lobby | The game server calls `POST /internal/matches/:id/end`, or its heartbeat stops listing the match, or it is 2 hours old, or its last member leaves. |
| A user's place | A user is in one open lobby; starting the lobby, leaving it or its end frees them. The host role passes to the next member when the host leaves. |

A sweep every 30 s drops expired lobbies, and a lookup of an expired one answers `not_found` at once.

**Capacity counts what the backend assigned.** `allocate(matchId)` records the match against a server, so two quick
starts cannot both take the last slot even though no player has reached the game server yet. A slot comes back when the
lobby ends (any of the cases above) or when the server stops listing the match in its heartbeat after a 5 minute grace
(time to join; it also drops a match nobody ever joined). A heartbeat that lists a match the backend does not know (it
restarted since) adopts it, so a restart does not hide running matches from the count. The game server reports what it
runs; it does not report a load number.

**After a backend restart** every lobby is gone: `GET /lobbies/:id`, `POST /lobbies/:id/ticket` and `leave` answer 404
`not_found`. What a client does:

1. A client already connected to its game server keeps playing; the match belongs to the game server, not the backend.
2. A client that polls the lobby (waiting room) or asks for a ticket and gets `not_found` shows "this lobby is gone" and
   returns to the menu, where it can create or join again (its old membership is gone with the lobby, so it is not
   blocked by `already_in_lobby`). The same happens when a lobby expired or the match ended.
3. A client that lost its game-server connection after a restart cannot get a new ticket for that match. The match
   keeps running on the server and is counted again from the next heartbeat, but this backend cannot rejoin a player to
   it. Persisting lobbies in Postgres is the fix and is not built.

## The game-server ticket

The ticket is an HS256 token (header pinned, constant-time compare). `verifyToken` rejects one without a numeric `exp`
and `iat`, of another kind, or expired. What a game server (the stub, and the Godot server later) must do:

1. Take the ticket from the **first WebSocket message** (`{"type": "join", "ticket": "..."}`), never from the URL,
   which proxies and access logs record. Read at most a few KiB before a socket is admitted, and close one that stays
   silent (the stub: 5 s, close code 4408).
2. Verify the signature and expiry, then that `serverId` is its own id. Another server's ticket is refused even though
   it holds the same secret.
3. Remember each `jti` until the ticket's `exp` and refuse a second use. A refusal before this step does not spend it.
4. Keep one live socket per seat (`matchId` and `sub`): a newer join closes the older one (code 4409).

Every refusal is close code 4401 with the reason as text (`bad ticket`, `ticket is for another server`, `ticket already
used`), so a client log says why. A client that wants a second connection asks `POST /lobbies/:id/ticket` again.

**Trust model.** `TICKET_SECRET` on a game server means that server can mint a valid ticket for any server, match and
user, so a compromised game server can enter any match. The `serverId` check stops a ticket meant for one server being
replayed on another (a rogue server that is handed a ticket cannot use it elsewhere); it does not stop a server that
holds the secret. `GAME_SERVER_SECRET` is also shared: its holder can register any `url` in the heartbeat (the backend
only checks it is a `ws://` or `wss://` URL) and so receive players and their tickets. What limits the damage later:
a ticket key per game server, derived as `HMAC(TICKET_SECRET, serverId)` so a server holds only its own and the
backend signs with the target's, or Ed25519 tickets (the game server then holds only a public key, but Godot needs an
extension for it). Neither is built; until then game servers are trusted and run only by us.

## Match settings: the host's rules reach the room

The host of a night chooses its rules (`MatchSettings`: zombie intensity, alive cap, break) and they travel with
the ticket, so the game server needs no second channel:

0. `PUT /lobbies/:id/settings` (the host only, while the lobby waits; the body is the three keys) keeps the rules on
   the lobby as the host moves the panel of the lobby screen; every member reads them in `lobby.settings` on a poll.
   `403 not_host`, `409 already_started` and `400 bad_settings` otherwise, and nothing changes.
1. `POST /lobbies/:id/start` takes `{"settings": {"count_multiplier", "max_alive", "break_seconds"}}` from the
   host (without it, the ones set while waiting; without those, today's game). The backend (`src/settings.ts`)
   accepts exactly those three keys inside the game's bounds (0.25 to 5; a whole 0 to 120; 0 or 1 to 120) and answers
   `400 bad_settings` otherwise, leaving the lobby open. They are fixed when the match starts; the lobby view shows
   them.
2. Every ticket of the match (`/lobbies/:id/ticket`) carries the same `settings` claim, signed with the rest.
3. The game server's `TicketVerifier.admit` returns them as a `MatchSettings`; the ticket that opens the room gives
   it to `NightHost.match_settings` before the night is built, and every WELCOME carries them from there. A ticket
   whose rules the game cannot take (the two sides' bounds drifted) is refused as `ticket carries rules this server
   does not take`, not played with other rules than the host asked for.

`JSON.parse` gives every number as a float, so `max_alive` arrives as `12.0`: the verifier makes a whole one an int
before `MatchSettings.from_dict` (strict) sees it. The first version of this change missed it and a ticket from the
backend would have been refused; `tickets.json` now holds a ticket the backend signed with settings. What is not
done: none. The lobby screen's panel is the host's way in (`LobbyScreen.rules`, `TogetherApi.set_settings`); a
lobby reads its rules back with `MatchSettings.from_json`, which makes the whole float a whole number the same way.

## What is not decided or not proven

- **Starting game servers on demand.** The spike uses a static pool that announces itself. Creating a Railway service
  or deployment per match goes through Railway's API and creates cloud resources: a maintainer decision, not made here.
  A single headless Godot process can host several matches; the capacity number in the heartbeat is what the backend
  respects.
- **URL mappings are static.** The Developer Portal maps a prefix to a host, so the address given to a player inside
  Discord is a path under `<client_id>.discordsays.com`, one mapping per game server (or one mapping to a small
  gateway). Prefix stripping and mapping limits were not verified on the live proxy; check on the first real deploy.
  WebSockets work through the proxy; WebRTC and WebTransport do not
  ([networking guide](https://docs.discord.com/developers/activities/development-guides/networking)).
  The backend serves `/api/...` as `/...` (`stripApiPrefix`, tested), so the `/api` mapping works whether or not the
  proxy strips the prefix; the game server takes any WebSocket path.
- **Outbound IP.** Discord warns that a changing egress IP (common on cloud functions) can be banned by Cloudflare
  for up to an hour and recommends a static one for all server traffic
  ([production readiness](https://docs.discord.com/developers/activities/development-guides/production-readiness)).
  Whether Railway offers one on our plan was not checked.
- **`instanceId` is a client claim.** Discord says to treat client data as unverified, so the lobby-per-instance
  shortcut only decides which lobby a signed-in user lands in; it grants nothing.
- **Lobbies live in memory** of one backend replica (lifetimes: [lifecycle](#lobby-and-match-lifecycle)), and clients
  poll. More than one replica needs lobbies in Postgres or Redis; push updates need a WebSocket or SSE channel. Both
  are next steps, not blockers.
- **Ticket signature.** HS256 on purpose: Godot can verify it with `Crypto.hmac_digest`; Ed25519 would need an
  extension. The ticket secret is shared between backend and game servers, so it is an environment variable on both
  (trust model: [the ticket](#the-game-server-ticket)).
- **Not done:** rate limiting on `/auth/discord`, match results flowing back to the backend, telemetry, migrations
  (the spike creates its two tables on start).
- **Nakama was only measured idle and read, not built.** The custom-auth path through a before hook is what its docs
  describe; it was not prototyped.

## Deploying it (for a maintainer)

Nothing was deployed or created. To do it: a Railway project with a Postgres service and the backend (root directory
`spikes/backend` until it moves), variables `SESSION_SECRET`, `TICKET_SECRET`, `GAME_SERVER_SECRET` (random, 32+
characters, all three different), `DISCORD_MODE=live` (no default: unset refuses to start), `DISCORD_CLIENT_ID`,
`DISCORD_CLIENT_SECRET`, `DATABASE_URL`, `NODE_ENV=production`; health check path `/health`. In the Discord Developer
Portal: an application, the redirect URL, and URL
mappings for the backend and each game server.

## Gotchas found while building it

- The gamepad in an Activity (#479). The Activity is an iframe, and a browser lists a gamepad to an iframe only when
  the Permissions-Policy feature `gamepad` allows it (the default in current Chromium is every origin, so a host
  has to forbid it on purpose, by an `allow` attribute or a header, to block it); a blocked page's
  `navigator.getGamepads()` throws, and Godot's web runtime swallows the error, so no pad ever shows. A page without the
  keyboard focus is listed none either, and a pad needs one button press to appear. The Embedded App SDK has no
  gamepad command (only key-binding types). The head include of the export defines `window.deadnightGamepad()` (frame,
  focus, the policy's answer, pads, the exception's name) and the Play together screen reads it inside an Activity
  and says which case it is (`GamepadProbe`: blocked, click first, press a button, connected), so the maintainer can
  read the cause in Discord. `tools/web_smoke/activity.py --embed denied` shows the blocked line; `--embed gamepad
  --pad` the connected one. What Discord's clients grant is not in its docs: read it from that line.
- Copy and paste in an Activity (#516). The iframe may not use `navigator.clipboard` (a policy feature that
  defaults to the page's own origin), and the engine's web runtime cancels every key press, so Ctrl+V never makes a
  `paste` event. A page layer takes the paste event and copies from a gesture; the SDK's `shareLink` sends a room's
  code with no clipboard. [Web export](web-export.md#copy-and-paste-inside-a-discord-activity-516).
  `shareLink` answers when its window is closed, rejects with a plain `{code, message}` object, and never settles on a
  reply the SDK cannot parse, so the button shows the hint only while Discord has not refused and the lobby's probe
  line quotes its answer (#627). [Web export](web-export.md#share-in-discord-what-discord-answered-627).
- Discord's proxy compresses the backend's answers (`Content-Encoding: gzip`), and Godot's `HTTPRequest` then decodes a
  body the browser has decoded already and fails, which the game reads as "Could not reach the game's servers": every
  call through `/api` failed while the backend logged a 200 or 201. `HttpJson` sets `accept_gzip = false`.
  `tools/web_smoke/activity.py` loads the web build as an Activity (a local HTTPS stand-in for `<id>.discordsays.com`,
  gzip and chunked answers) and fails on it. A Discord sign-in code works once, and the answer the game could not read
  had used it: a retry sent the same code and got Discord's `400`, so the game now trades a code in once
  (`TogetherApi._spent_code`).
- Node 24 runs `.ts` by stripping types only: constructor parameter properties (`private readonly x` in the
  signature) and enums fail at runtime. `erasableSyntaxOnly` in `tsconfig.json` catches them in `tsc`.
- Fastify answers 400 to a request that sets `Content-Type: application/json` with an empty body, and validates the
  body before a `preHandler` runs. Authenticate in `onRequest` so a missing session is a 401, not a 400.
- Log every request except health checks and heartbeats, or the log is mostly heartbeats. In Fastify 5.12 the
  function form of the top-level `disableRequestLogging` is deprecated (removed in Fastify 6); pass
  `logController: new LogController({ disableRequestLogging: fn })` instead.
- A compose stack needs its secrets to stay the same for as long as its Postgres volume lives: the database keeps the
  first `POSTGRES_PASSWORD` and a recreated backend with a new one fails with `auth_failed`.

## Sources

- Discord: [networking](https://docs.discord.com/developers/activities/development-guides/networking),
  [building an Activity](https://docs.discord.com/developers/activities/building-an-activity),
  [Embedded App SDK](https://docs.discord.com/developers/developer-tools/embedded-app-sdk),
  [production readiness](https://docs.discord.com/developers/activities/development-guides/production-readiness).
- Railway: [pricing](https://docs.railway.com/reference/pricing/plans),
  [health checks](https://docs.railway.com/deployments/healthchecks),
  [private networking](https://docs.railway.com/networking/private-networking),
  [Nakama template](https://railway.com/deploy/nakama-1).
- Nakama: [authentication](https://heroiclabs.com/docs/nakama/concepts/authentication/),
  [server framework](https://heroiclabs.com/docs/nakama/server-framework/introduction/),
  [TypeScript runtime](https://heroiclabs.com/docs/nakama/server-framework/typescript-runtime/),
  [Docker install](https://heroiclabs.com/docs/nakama/getting-started/install/docker/),
  [repository (Apache-2.0)](https://github.com/heroiclabs/nakama).
- Colyseus: [Discord Activity guide](https://docs.colyseus.io/getting-started/discord-activity),
  [rooms](https://docs.colyseus.io/room), [repository (MIT)](https://github.com/colyseus/colyseus),
  [pricing](https://www.colyseus.io/pricing).
