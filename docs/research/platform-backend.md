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
- `POST /lobbies` always creates a lobby (the Activity's `instanceId` is not read any more, #1178),
  `POST /lobbies/join-by-code`, `GET /lobbies/:id`, `POST /lobbies/:id/leave`, `POST /lobbies/:id/page-closed` (the closing
  page's own Leave, a `text/plain` beacon carrying the token in its body; always `200 {left}` for a good token),
  `POST /lobbies/:id/start` (host only; allocates a game server). `GET /lobbies` leaves out a waiting lobby nobody has
  been heard from in for 15 s (hidden, not ended:
  [what the list shows](../design/lobby.md#what-the-list-shows-and-the-pages-last-word-1188)).
  A user is in one lobby at a time, open or started: creating or joining another takes them out
  of it, so no call is refused for it ([every state](../design/lobby.md#leaving-and-moving-every-state-and-what-ends-it)).
- `POST /lobbies/:id/ticket` returns `{address: {url, activityPath}, ticket}` for the caller's seat. The ticket names
  the game server it is for (`serverId`) and has a unique id (`jti`); see [the ticket](#the-game-server-ticket).
- `PUT/GET /saves/:slot`: a save is `{revision, schemaVersion, data}`; a stale `revision` is a 409 instead of lost
  progress. Format rules: [Save format](#save-format). The `profile` slot has more rules: [Progression](#progression-the-profile-slot-round-reports-and-the-xp-clamp).
- `POST /internal/matches/:id/report` (shared secret): a game server's XP for each seat at a round's end or the night's
  end, paid once ([Progression](#progression-the-profile-slot-round-reports-and-the-xp-clamp)).
  `GET /internal/users/:userId/saves/challenges` (shared secret): the seat's challenge board, which the game server
  follows ([the board](#progression-the-profile-slot-round-reports-and-the-xp-clamp)).
- `POST /internal/servers/heartbeat` (shared secret): a game server announces itself, its capacity and the ids of the
  matches it is running. `POST /internal/matches/:id/end` (shared secret): a match is over, its slot is free. A night
  that ran its end-of-night intermission out sends `{finished: true, present: [user ids still in the room]}` and its
  lobby opens again for them (open, same code, host and settings; a user who has moved to another
  lobby is not put back, and a reopened lobby nobody reads within a minute is dropped); any other end drops the lobby
  ([end of a night](end-of-night.md)). `POST /internal/matches/:id/left {userId}` (shared secret): a person's seat in the
  match is empty (Leave, a closed tab, a dropped connection not taken back): they leave the lobby at once and the last
  one out ends it; unknown matches and users are ignored.
  How lobbies and capacity end: [Lobby and match lifecycle](#lobby-and-match-lifecycle).
- `src/stub-gameserver.ts` stands in for headless Godot: it heartbeats, and admits only a valid ticket
  that is unexpired, for this server and unused (`jti`), sent as the first WebSocket message.
- Configuration only from environment variables; JSON logs that never include headers or bodies (redaction of the
  code and tokens is configured as a backstop); `/health` and `/ready` (checks the database); graceful shutdown on
  `SIGTERM`.

Run it: `npm ci && npm test` in `spikes/backend/` (sign-in, lobbies, handoff, forged and expired tickets, capacity,
saves, guest accounts that last, config that fails closed, the live Discord client and its timeout).
`scripts/dev-compose.sh up --build -d` starts Postgres, the backend and the stub game server with development secrets
kept in the workspace `scratch/` folder for the life of the stack (a second `up`, `restart` and `down` keep the data,
`down -v` wipes both), then `npm run e2e` has two players sign in, share a lobby, start it and connect to the game
server. Measured on the compose stack: the e2e run passed, a save survived a backend restart (Postgres), and
`docker compose stop` took 0.7 s because the process closes on `SIGTERM`.

## Join flow: from the Activity to a running match

The Activity opens on the main menu, like every platform (#495), and plays the website's Play together (#1178). The
sign-in runs in the background from the menu (`StartupSignIn`, with Discord; `main.gd` sets `TogetherApi.activity` when
the page has `instance_id`), and that is all the Activity does by itself: Play together shows the code field and the
Create button and makes no lobby until the player asks ([the lobby](../design/lobby.md)). Players meet by a code, a
link (`?room=CODE`) or Quick join; a code opens its night (waiting, or in progress with its round) with Join. Nothing
joins a lobby before a player asks, so people who only opened the Activity hold no seat. The instance id was used to
find or make "the voice channel's lobby" (`POST /lobbies {instanceId}`, `POST /lobbies/preview
{instanceId}`); two players who each pressed Play together got a lobby each, because the first one's was not yet
there to find, so it was removed in the game and the backend.

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
    A->>B: POST /lobbies (a lobby of the player's own; friends join it by its code)
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
   id), a name the player may choose or `Guest 1234`, limited to 30 sign-ins an hour from one address and 2000 new
   accounts in all. A guest comes back to the same account for **7 days after its last sign-in**
   ([Guest accounts](#guest-accounts)).
   The backend runs `DISCORD_MODE=live` with guests switched on (`GUEST_SIGN_IN=1`); `DISCORD_MODE=off` is the same
   with no Discord at all. Browsers on another origin than the backend need it in `CORS_ORIGINS`; inside a Discord Activity
   everything goes through the proxy (`/api`, `/server`) and is same-origin.
2. **A night.** *Create a night* is `POST /lobbies`: a lobby that waits ([the lobby](#the-lobby-before-the-night)) until
   its host calls `POST /lobbies/:id/start`, which allocates the least loaded game server with room; the lobby keeps a
   short code. A new night is **public**; its host makes it private with `PUT /lobbies/:id/visibility` (or
   `visibility` in the create). *Quick join* is `POST /lobbies/quick`: a public night with
   room (open or already started), else a new public one. The public nights are listed by `GET /lobbies`
   ([the list](#the-list-of-nights-1179)). *Join with the code* is `POST /lobbies/join-by-code`, and it
   works on a night that has already started (a started night takes newcomers while the game server says it has room:
   its heartbeat carries `players`, the count in each match); the screen reads the code with `POST /lobbies/preview`
   first. A Discord Activity does the same as the website.
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
   ([rooms in one process](crowd-budget.md#rooms-in-one-process-561), and
   [with eight players a room](crowd-budget.md#rooms-of-eight-on-railway-712)): `ROOM_CAPACITY` 3 and `ALIVE_BUDGET` 120
   (the most
   alive in all the rooms together, each cut to its share; a room with a browser in it stands 40 whatever it says),
   and `MAX_ALIVE` for a cap on any one room. Bots are limited the same way, whatever the host's Bots setting asks
   (`BotLimits`): `MAX_BOTS` (0 to 7, default 7) caps one room, `BOT_BUDGET` (default none) shares a number of bots
   among the open rooms, and `BOTS_OFF=1` is the kill-switch: no room seats a bot, and a restart is the only thing it
   needs. The measured cost of three bots is [in the bot research](bots.md#server-cost).

Environment of the services (names only; the secrets are Railway variables, never in the repository):

| Service | Variables |
| --- | --- |
| `backend` | `SESSION_SECRET`, `TICKET_SECRET`, `GAME_SERVER_SECRET` (all different, 32+ characters), `DATABASE_URL` (the Postgres reference), `DISCORD_MODE`, `DISCORD_CLIENT_ID`, `DISCORD_CLIENT_SECRET`, `GUEST_SIGN_IN=1`, `CORS_ORIGINS` |
| `deadnight-server` | `BACKEND_URL`, `GAME_SERVER_SECRET` and `TICKET_SECRET` (references to the backend's), `PUBLIC_URL` (`wss://` its public domain), `ACTIVITY_PATH=/server`, `ROOM_CAPACITY` (3), `ALIVE_BUDGET` (120), optionally `MAX_ALIVE`, `MAX_BOTS`, `BOT_BUDGET`, `BOTS_OFF` |

A path variable set from Git Bash on Windows is rewritten (`/server` became `C:/Program Files/Git/server`): set them with
`MSYS_NO_PATHCONV=1` or from PowerShell.

**Cost** (Railway, Hobby plan, measured on these services idle): backend about 35 MiB, Postgres about 35 MiB and the game
server a Godot process of a few hundred MiB; at $10 per GB-month and $20 per vCPU-month that is roughly $3 to $6 a month
with nobody playing, and a busy night adds a fraction of a core for each room in play.

## Guest accounts

A Guest account lasts **7 days without a sign-in** and is the same account each time it is signed in to in that time
(#1080; the maintainer: guests are tracked on the server, expire after 7 days if not logged in again, and are normally
reached again through local storage). A Discord account never expires, and moving a guest to Discord is not built.

- **The credential.** `POST /auth/guest` answers with `guestToken` beside the one-hour `token`: an HS256 token of kind
  `guest`, signed with the session secret, whose `sub` is the account's id and whose lifetime is 7 days
  (`guestExpiresIn`, `GUEST_TTL_SECONDS`). A client cannot make one for another guest's id without the secret, and a
  session token, a ticket or a bare id is not one (the kind is part of what is signed). It is no session: the API
  refuses it as a bearer.
- **Coming back.** The client sends `{name?, guestToken?}`. A credential that checks out for an account that is still
  there, is a guest's and is in date signs that account in (200, `returning: true`); anything else, a forged, expired,
  foreign or unknown credential included, makes a new guest (201), never another's account. Every sign-in sends a fresh
  credential and sets the account's `last_seen` (`users.last_seen`), which restarts the 7 days. The chosen name updates
  on each sign-in; a returning guest that gives none or an unusable one keeps its name.
- **Expiry.** A Guest account whose `last_seen` is 7 days old or older is deleted with its saves (`ON DELETE CASCADE`):
  at its own sign-in (a good signature on a credential that ran out still deletes an idle account, so it is gone when
  anyone looks) and by an hourly sweep that also runs once when the backend starts (a backend redeployed more often than
  hourly would never reach the first tick). The sweep matches only the `guest:` namespace, so no Discord account is
  touched. Tests move the backend's clock (`Deps.now`) a millisecond either side of the 7 days.
- **Limits.** The address limit counts every guest sign-in, a returning one too; the limit for all addresses counts
  only new accounts, so a flood of new guests does not shut returning players out.
- **Storage.** The game keeps the credential in `user://guest_account.json`
  (`game/net/guest_account.gd`), which on the web build is the browser's IndexedDB, one credential for each backend.
  A Discord Activity keeps none (it signs in with Discord). A test run keeps none unless a test names a file. Clearing
  the browser's site data, or another browser, is a new guest: the account is reached only by the credential.
- **Migration.** `users.last_seen` is added by `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`, so accounts made before it
  count as seen when the backend first starts with it (their 7 days begin then).
- **Proved** by `spikes/backend/test/guest_account.test.ts` (with `TEST_DATABASE_URL` also against Postgres), by
  `game/tests/net/test_guest_account.gd` (the real backend and the game's sign-in path) and by
  `tools/web_smoke/guest_account.py`: the web build in headless Chromium signs in as a guest, a save is written to the
  account, the page is reloaded and the probe reads the same account (and the save) back, while a second browser with
  empty storage is another account ([how to run it](testing-multiplayer.md#playing-online-today)).

## Player names

One name per player, the same on every screen of a night (#485).

- **Where it comes from.** A web or desktop player with no saved name is asked on the first Play together ("Skip, call me
  Guest" is an answer too) and can change it under More in the menu; it is kept in the profile and sent to
  `POST /auth/guest`; a guest who comes back and gives none keeps the name its account has
  ([Guest accounts](#guest-accounts)). In a Discord Activity the backend reads it from Discord: the player's
  nickname in the guild the Activity runs in (`guildId` in `POST /auth/discord`, read with the `guilds.members.read`
  scope), else the global name, else the username. If the player refuses the scope the bridge asks for `identify` alone
  and the name falls back; the sign-in never fails for a name.
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

## Progression: the profile slot, round reports and the XP clamp

Design: [Storage and trust](../design/progression.md#storage-and-trust). Code: `spikes/backend/src/progression.ts`;
tests: `test/progression.test.ts` (memory store, real sockets with the stub game server, and Postgres when
`TEST_DATABASE_URL` is set). **The backend is never written per kill**: XP reaches it in one post per seat at a round's
end and at the night's end, or in one write of a solo client's profile at a round's end.

**The slot.** `PUT/GET /saves/profile` is the one slot the backend reads. The profile is the game's `Profile.to_dict`:
`{xp, equipped, done, opening_night, bonus_day}` (schema 1, the version both game slots use, so `SAVE_SCHEMA_VERSIONS`
needed no new entry; the `challenges` slot stays an ordinary save the backend does not read, but a game server reads
it and writes it, [below](#the-challenge-board-a-game-server-follows)). Raw XP only: the level,
the icon and the next reward are derived (`levelOf` is a copy of `LevelCurve`, held equal by a test that reads the
GDScript). A write must read (422 `invalid_profile` names the field) and take nothing away (422 `profile_regressed`:
XP, the opening night, the day number or a finished challenge). A **Guest account** has a profile slot and earns like any
other account; nothing in the code tells them apart.

**The solo client's write and the clamp.** A write may add at most **120 XP for each minute of wall clock since the
account's last XP write** (the session's start for the first one), counting at most an hour, so the long-run rate is
120 a minute however long the silence (a strong four-player night is about 35 a minute, so this is three times that;
retune with the telemetry). The one-offs this write claims widen it by exactly their XP: 50 for the opening night, 100
for the first game of the day. More is 422 `implausible_progress` with `added` and `allowed`; a refused write is
acceptable later, because the allowance grows with the clock. The **first game of the day** is the profile's
`bonus_day`: the day number (days since 1970, the dailies' own) is accepted once, only forward, and only within one day
of the backend's own UTC date (422 `implausible_day`). **No offline XP, no merge:** a stale revision is 409; the client
reads the account's own latest and sends its change again on top. Equipping something adds no XP, writes no ledger line
and does not restart the clock.

**The game server's round report.** `POST /internal/matches/:matchId/report` with the game-server secret (a client
cannot post XP for an online night; the secret is what "a server the platform started" means here):

```json
{ "kind": "round", "round": 3, "seats": [
  { "userId": "<account id>", "xp": 140, "openingNight": true, "bonusDay": 20761,
    "done": ["daily_kills"], "lines": { "points": 12000, "boards": 6 } } ] }
```

- `kind` is `round` (a round ended) or `night` (the night ended); `xp` is whole XP earned since the seat's last report,
  0 to 1,500, without the two one-offs. `openingNight` and `bonusDay` are claims: the backend knows the profile, so it
  pays the 50 and the 100 itself, once. `bonusDay` is the day number of that round's end (the client's own local day if
  the server has it, else UTC's). `done` are challenge ids finished; `lines` are what the round did, kept in the ledger.
- **Idempotency.** The key is (match, kind, round, account). A second post with the same key pays nothing and answers
  `duplicate` with the first amount, per seat, so a report that failed halfway is posted again whole and pays only what
  was missing. The ledger line and the profile write are one transaction in Postgres.
- **The cap.** One account is paid at most **1,500 XP in a match** (`XpRules.NIGHT_CAP`), every report together; a
  report past it is cut to what is left (the answer's `credited` says). The report adds on top of the account's own
  latest profile, so a client write in between only makes the client's next write a 409.
- The answer is `{seats: [{userId, status, credited, openingNight, firstGameOfTheDay, xp, level}]}`; `status` is `paid`,
  `duplicate` or `unknown_user` (an account that is gone, a Guest past its 7 days; the other seats are still paid).

**The ledger** (`ledger` table, `Store.putSave(..., ledger)`): append only, one line for each report seat and each solo
write that added XP, `(user, match, kind, round, xp, reason, at)`; its primary key is the idempotency key, a solo line
has the empty match and its new revision as the round. The balance is the profile's `xp`; the ledger says why. The
design's `night_log` (the history screen) and `match_report` (signed per-match facts) are not built: nothing reads them
yet, and the ledger holds the same facts.

**The ticket** carries `level`, `icon` (`level_NN`, a file of `game/assets/ui/levels/`) and `xp`, read from the stored
profile when the ticket is minted, never from the client; an account with no profile, or one that does not read, is
level 1. The stub game server passes them on in its welcome. The lobby's member list carries the same `level` and `icon`
for each member (`ProgressService.knownLevel`, read when the member joins and moved by every report), so the lobby shows
the tag the ticket will carry; a Guest account's is its own like any other. How the game server shows them:
[the level and icon beside a name](multiplayer.md#the-level-and-icon-beside-a-name-1077).

The ticket also carries the calling card, emblem and frame the player chose (`card`, `emblem`, `frame`, from the
profile's `equipped`; only plain names `[a-z0-9_]{1,40}` are signed, nothing when none is chosen) and, only then, `done`,
the last 256 finished challenges, which the game server holds the choices to (`TicketClaims`,
`ProgressService.claimsFor`); the lobby's member list carries `card`, `emblem` and `frame` as chosen. [Calling cards](calling-cards.md#how-a-card-reaches-every-client).

What the game server must send, and when: [the game server's tally](../design/progression.md#who-awards-xp-and-live-xp)
(#1059) posts one report a seat at each round's end (`kind: round`, `round: n`) and one at the night's end (`kind:
night`, `round: n`), retries a post until it is answered, and keeps unsent reports while the backend is down.

### The challenge board a game server follows

The game server runs the challenge tracker for the seats that hold an account (#1076, [the design](../design/progression.md#the-save)),
so it needs the account's board when the seat sits down and has to put it back. A player's session token is the only
way into `/saves/:slot`, so the server has its own two doors, both with the game-server secret:

- **Read: `GET /internal/users/:userId/saves/challenges`** answers the slot's envelope (`{revision, schemaVersion, data}`),
  or 404 `{"error": "not_found"}` for an account with none (the server starts a fresh board; **only that body** means
  "none": a 404 from a backend from before the route has Fastify's own body, and the server then follows no board
  rather than start one that a report would write over the real one). Only this slot: the profile's XP rides the ticket.
  The server asks once, when the seat sits down, with a 3 s timeout, and the night does not wait for the answer; a seat
  whose board did not come is not followed and never written.
- **Write: a seat's `board`** in the round report (`{schemaVersion, data}`, the slot's envelope without a revision).
  The backend replaces the stored board with it (reading the revision itself and writing on top of whatever the
  player's own client wrote since). The board is a snapshot, so a report applied again (`duplicate`) writes it again,
  which is how a board lost with the first try gets through. A board that is refused (an unknown `schemaVersion`, or over
  64 KiB) is answered `board: "refused"` on that seat and **never takes the XP with it**. `done` (the challenge ids
  finished since the last report) goes to the profile's list as before. A report may weigh up to 1 MiB.

## The lobby before the night

Design: [the lobby](../design/lobby.md). *Create a night* is `POST /lobbies` alone: the lobby stays **open** until its
host calls `POST /lobbies/:id/start`, and every member polls `GET /lobbies/:id` meanwhile.

- **The view** (`GET /lobbies/:id`, members only) has `members` as `[{userId, name, seat, host, away}]` in the order people
  came (seats close up when someone leaves), `hostId`, `state` (`open` or `started`), `players` (the game server's count
  once started), `round` (the night's round, null until the game server has said one), `matchId` and the usual code.
- **Seats.** A lobby holds 1 to `MAX_PLAYERS` = 8 **people** (`src/lobbies.ts`, the game server's `NightHost.MAX_PLAYERS`;
  #690): the default for a lobby made without `maxPlayers` and for Quick join, and the most `POST /lobbies` takes (`400`
  above). Bots hold no seat (#1179): the host's `bots` setting (0 to 7) is kept in the settings and the game server runs
  that many on top of the eight, so a lobby (and a night, through the heartbeat's `players`, which is people) is full on
  people alone. A lobby's own `MAX_SEATS_EVER` (32) stays the guard on a started night's member list. The tests
  (`lobby.test.ts`, `server_browser.test.ts`) fill a default room with eight, turn the ninth away with `409 full` and
  refuse a limit of nine; with seven bots set eight people still fill it and the ninth is still turned away.
- <a id="the-list-of-nights-1179"></a>**The list of nights** (#1179, the Server Browser's data). `GET /lobbies`: the public
  nights,
  `{maxPlayers, total, nights: [{id, code, map, hostName, players, maxPlayers, bots, kind, state, round, full}]}`;
  `kind` is `lobby` (waiting) or `match` (in progress, with its `round`); the shape and the reasons are in
  [the lobby](../design/lobby.md#the-list-of-nights-the-server-browsers-data-1179). It is one
  pass over the in-memory lobbies (an expired one is dropped on the way, a silent member is not counted) and keeps
  nothing, so an ended or emptied night is gone from the very next call; at most 50 rows; limited to 20 asks in 10 seconds
  per account (`429 too_many_requests`). `PUT /lobbies/:id/visibility` `{visibility: "public" | "private"}` is the host's
  (`403 not_host`, `400 bad_visibility`); `POST /lobbies` also takes `visibility`. A new night is public. Quick join still
  exists and is removed with the Server Browser screen (#1180).
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
| Open lobby | Its last member leaves or moves to another lobby, or the member's page says it is going (`page-closed`), at once. The backstop: idle for 10 minutes (create, join, leave, start and a member's `GET` all count as activity). A member not seen for a minute is dropped while another is still there ([presence](#the-lobby-before-the-night)). |
| Started lobby | Its last member leaves or moves, or the game server says the last person's seat is empty (`/left`), or calls `POST /internal/matches/:id/end` (a finished night reopens the lobby), at once. The backstop: its heartbeat stops listing the match, or it is 2 hours old. |
| Reopened lobby | A member reads it (then it is an open one), else it is dropped a minute after it opened. |
| A user's place | A user is in one lobby, open or started. Leaving it, its end, or creating or joining another frees them: a move takes the player out of the old lobby first (the host role passes to the next member), and a join refused as `full` leaves them where they were. |

The whole sweep, state by state and way out by way out, is in [the lobby design](../design/lobby.md#leaving-and-moving-every-state-and-what-ends-it).

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
   returns to the menu, where it can create or join again (nothing holds a player for the lobby they were in, and its
   membership is gone with the lobby). The same happens when a lobby expired or the match ended.
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

The host of a night chooses its rules (`MatchSettings`: zombie intensity, alive cap, break, bots and the map) and they
travel with the ticket, so the game server needs no second channel:

0. `PUT /lobbies/:id/settings` (the host only, while the lobby waits; the body is the three keys) keeps the rules on
   the lobby as the host moves the panel of the lobby screen; every member reads them in `lobby.settings` on a poll.
   `403 not_host`, `409 already_started` and `400 bad_settings` otherwise, and nothing changes.
1. `POST /lobbies/:id/start` takes `{"settings": {"count_multiplier", "max_alive", "break_seconds"}}` from the
   host (without it, the ones set while waiting; without those, today's game). The backend (`src/settings.ts`)
   accepts exactly those three keys, and optionally `bots` (a whole 0 to 7; left out it means none and is kept left out,
   so a client from before it still passes) and `map` (an id of `PLAYABLE_MAPS`: the maps the game can play; a map that
   is listed but not built is refused), inside the game's bounds (0.25 to 5; a whole 0 to 120; 0 or 1 to 120) and answers
   `400 bad_settings` otherwise, leaving the lobby open. They are fixed when the match starts; the lobby view shows
   them.
2. Every ticket of the match (`/lobbies/:id/ticket`) carries the same `settings` claim, signed with the rest.
   And the same `hostLevel` claim: [the lobby host's level](#the-hosts-level-decides-the-map-1098) when the match started.
3. The game server's `TicketVerifier.admit` returns them as a `MatchSettings`; the ticket that opens the room gives
   it to `NightHost.match_settings` before the night is built, and every WELCOME carries them from there. A ticket
   whose rules the game cannot take (the two sides' bounds drifted) is refused as `ticket carries rules this server
   does not take`, not played with other rules than the host asked for.

`JSON.parse` gives every number as a float, so `max_alive` arrives as `12.0`: the verifier makes a whole one an int
before `MatchSettings.from_dict` (strict) sees it. The first version of this change missed it and a ticket from the
backend would have been refused; `tickets.json` now holds a ticket the backend signed with settings. What is not
done: none. The lobby screen's panel is the host's way in (`LobbyScreen.rules`, `TogetherApi.set_settings`); a
lobby reads its rules back with `MatchSettings.from_json`, which makes the whole float a whole number the same way.

### The host's level decides the map (#1098)

The back rooms open at level 10 ([the design](../design/maps.md#levels-open-maps)). The host's level decides, not the
holder's: a guest below a map's level still plays a hosted night there.

- `src/settings.ts` keeps `MAP_UNLOCK_LEVELS` (`drive_in` 1, `small_indoor` 10), the game's `MapInfo.unlock_level`;
  `PLAYABLE_MAPS` is its keys. `test/map_gate.test.ts` reads the game's `game/world/maps/*.tres` and holds the ids and the
  levels equal (the `backend` job checks out `game/world/maps` for it, and a change to those files starts the job).
- `PUT /lobbies/:id/settings` and `POST /lobbies/:id/start` read the requester's level from the stored profile
  (`ProgressService.levelFor`, the same curve as the ticket's `level`; no profile is level 1) and refuse a map it does not
  open as `400 bad_settings` (`map needs level 10`), so the picker's refusal and the server's agree. Rules the host set
  while waiting and a new host inherited (the host left) start on the drive-in lot when the new host's level does not open
  their map, the other rules standing, as the game server does with a ticket.
- The level is read **at the start** and kept on the match (`Match.hostLevel`); `/lobbies/:id/ticket` signs that number
  into the ticket of every member, so the order the players arrive in decides nothing and XP the host earns in the night
  moves the badge (`level`) and not the gate. A night that reopens its lobby reads the host again at its next start, so
  a host who passed the role on changes it for the next match.
- A backend from before this signs no `hostLevel`; the game server then counts the host as level 1
  (`TicketVerifier.NO_LEVEL`), so the back rooms are never opened by a missing claim (#1107).
  `test_map_unlock_net.gd` runs the rule over this backend: a level-3 host and a level-12 guest, and the reverse.

### A setting is never dropped (#944)

On 2026-11-03 the maintainer made a lobby, set a second map, bots and intensity, and every night was the usual one on
the drive-in with no bots. Nothing in the code lost them: the live `backend` service had been deployed once, on
2026-11-02 at 08:34 UTC, from a build that came before the host's rules (#559), and nothing deployed it again (the `ci`
workflow deployed `web` and `deadnight-server`). That backend answered `PUT /lobbies/:id/settings` with a bare `404 Not
Found`, ignored the `settings` a start carries, and sent lobbies with no `settings` at all, so every ticket was without
rules and the room was built on the defaults: all six settings lost at once, by one cause. The lobby said "Something
went wrong (Not Found). Try again." and went on.

What keeps it from happening again:

- **The backend is deployed with the game.** The `deploy-backend` job of `ci` (`deploy/backend/deploy.sh`) publishes
  `spikes/backend` to the `backend` service on every green push to `main`, beside `web` and `deadnight-server`, with the
  same skip of a build older than the live one (`deploy/check_head.sh`). The Postgres service keeps its data.
- **A deploy compares the keys.** `/health` lists `settingsKeys`; `deploy/backend/check_keys.sh` compares them with the
  keys of `MatchSettings.KEYS` in the game's source and fails the deploy job when a backend lacks a key the game has (or
  has one the game lacks); a backend from before the list fails it too. `deploy/backend/test_check_keys.sh` is the
  script's own test, in `conventions`.
- **An unknown or wrong setting is an error that names it.** The backend answers `400 bad_settings` with `detail`
  (`unknown setting a_rule`, `bad bots`, never a value) on a change and on a start, and logs it; the client shows
  it. The game server refuses a ticket that carries a key it does not know (`ticket carries a setting this server does not
  know: a_rule`) and a dedicated server stops on an option it cannot take (`--map nowhere`).
- **A backend that keeps no rules is said to the host.** A lobby with no `settings` key (a backend from before the
  rules), or a `404` on the change, shows "This server is out of date and keeps none of these rules" on the lobby screen
  and makes its panel read-only, instead of letting the host's choices vanish.
- **One test per setting, through the real stack.** `tests/net/test_lobby_settings_reach_the_night.gd` runs the real
  backend, a real game server and the real lobby screen with its panel, for each key of `MatchSettings.KEYS` twice
  (changed while the lobby waits, changed as Start is pressed), plus the last change winning and a start with no rules
  in it, and reads the room's rules, the lot it built, the bots it seated and the lot the client built from the WELCOME;
  a key with no case fails the suite, and one more compares the backend's list with the game's. A setting that is added
  (the perk limit, #913) therefore cannot ship until it reaches the night. `tools/web_smoke/lobby_settings.py` does the
  same from the web build in a browser, against a local stack or a deployed one.

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
- **`instanceId` names nothing.** It used to pick the lobby a signed-in user landed in (a client claim Discord says
  to treat as unverified); #1178 removed it, so the backend ignores the field if an old client still sends it.
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
  Discord's client answers every command, `shareLink` among them, with RPC 4006 "Not authenticated or invalid
  scope" until the Activity has run `authenticate`: the sign-in code from `authorize` is swapped for a token here
  (`POST /auth/discord` returns it as `access_token`, the client secret stays on the backend) and the game gives
  the token back to the bridge ([#627](web-export.md#share-in-discord-the-activity-must-authenticate-627)).
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
