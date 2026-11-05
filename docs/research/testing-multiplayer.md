# Testing multiplayer

How to put two or more players in one night and look at it. The design is in [Multiplayer](multiplayer.md); this page
is the commands. The game also has a public server on Railway (see [Playing online today](#playing-online-today)).

All commands run from the repository root with the pinned Godot (never a Steam copy):

```text
godot=$(uv run --project ../gdstudio/python gds tool path godot)        # bash
$godot = uv run --project ..\gdstudio\python gds tool path godot        # PowerShell
$godot --headless --path game --import                                  # once, and after pulling
```

## Playing online today

The game has rooms: nobody types an address. The platform backend (project `gdstudio-net-test`, service `backend`, with
Postgres) makes the nights and the game servers (`deadnight-server`) run them, one process hosting several nights
(see [Platform backend](platform-backend.md#rooms-the-game-and-the-backend-together)). To play:

1. Open the web build, <https://web-production-f401d1.up.railway.app>, and wait for the menu.
2. Choose **Play together** (the second item). Then one of:
   - **Server browser** (the Play tab's second item, or the first on this screen): the public nights, lobbies that wait
     and nights in progress, one row each; press a row to land in it.
   - **Create a night**: the lobby opens with a code, an invite link and eight seats, you as host. **Copy the link** and
     send it. A friend who opens the link (`?room=CODE`) reads your lobby first (*Waiting room, Ann is hosting, 1 of 4
     here.*) and presses **Join**; or types the code under **Join with the code**. Everyone sees who is there within a
     couple of seconds. You press **Start the night** when they are in; they press **Play**.
3. Starting or joining builds the lot and warms it up (about 35 s in Chrome with a graphics card). Up to eight share a
   night, and a player who comes later reads *Night in progress, round N* on the same screen and joins it where it is
   (a preview left open follows the night by itself).

Inside a Discord Activity the game opens on the main menu like anywhere else, signed in in the background
(`?instance_id=` from Discord); **Play together** is the website's screen, with the code field and **Create a night**,
and makes no lobby until a player presses Create; the others join by its code or link. `tools/web_smoke/activity.py`
checks it: the menu first, then Play together with no lobby asked for, then Create makes exactly one
(`--website` runs the same steps as the website, for the capture beside it).

The server address is a developer setting: on the desktop the Play together screen has a **Server address** button
(the old Join screen, `ws://localhost:8910` is this machine's own server), and on the web `?dev` shows it.

From a desktop build or the editor, the same without the menu: `godot --path game -- --connect
wss://deadnight-server-production.up.railway.app`, and `--bot` lets the autopilot play (`--headless` too, no window).
`--report [seconds]` makes a client print a JSON line every few seconds (`player_id`, the `players` in the frame, the
zombies, points, the round trip and the gaps between ticks), which is how a headless run is read.

The web build and the game server must speak the same protocol version (`NetWire.VERSION`), and a merge deploys both,
a few minutes apart: for those minutes Join may answer that the server speaks another version (or that the game is out of
date, when the server is the newer: reload). To read what the server sees: `railway logs --service deadnight-server`
(one JSON line a `room_opened`, `joined`, `left` and every ten seconds a `stats` for each night).

`tools/web_smoke/rooms.py` plays the whole flow in headless Chromium with four pages (A creates a night, B opens the
invite link, C makes a night and D finds it in the Server Browser) and fails unless each pair sees exactly two players:

```text
uv run --project <kit>/python gds quiet --   uv run --with playwright==1.64.1 python tools/web_smoke/rooms.py <web URL or build/web> <backend https address> <out folder> --gpu
```

`tools/web_smoke/lobby.py` plays the lobby in headless Chromium with three pages (A creates and sees the seats, B joins
from the link and cannot start, A starts and B presses Play, C's preview left open says *Night in progress* and C joins
mid-match), under `gds quiet`, with the autopilot (`?bot`) playing so nobody idles and dies while the others load. It
runs against a deployed backend, or a local one: `node spikes/backend/src/main.ts` (env as in `test_lobby_online.gd`, with
`CORS_ORIGINS=http://127.0.0.1:8081`) and a game server with `BACKEND_URL`, `TICKET_SECRET`, `GAME_SERVER_SECRET` and
`PUBLIC_URL=ws://127.0.0.1:<port>`:

```text
uv run --project <kit>/python gds quiet -- uv run --with playwright==1.64.1 python tools/web_smoke/lobby.py <web URL or build/web> <backend address> <out folder>
```

`tools/web_smoke/guest_account.py` proves a Guest account lasts (#1080) against a backend of its own: a guest signs in
from the web build, a save is written to the account, the page is reloaded and the probe reads the same account and
save back; a second browser with empty storage is a new account. It serves the build on `127.0.0.1:8087` (list it in
`CORS_ORIGINS`):

```text
uv run --project <kit>/python gds quiet -- uv run --with playwright==1.64.1 python tools/web_smoke/guest_account.py <web URL or build/web> <backend address> <out folder>
```

`tools/web_smoke/online.py` joins one game server by its address (the developer path) and plays a night, reading the
page's probe (`players`, `alive`, `rtt_ms`) every second:

```text
uv run --project <kit>/python gds quiet --   uv run --with playwright==1.64.1 python tools/web_smoke/online.py <web URL or build/web> <server address> <out folder> --seconds 90 --gpu
```

Every probe runs under `gds quiet` (the kit's `docs/godot/no-focus.md`): a page that takes pointer lock confines the
real cursor, and a hook refuses a probe started without it.

## Two desktop windows on one machine

Open three terminals.

```text
# 1. The server: one night, up to eight players. Headless, plain ws://, port 8910 unless told otherwise.
$godot --headless --path game -- --server

# 2. Player one.
$godot --path game --resolution 960x540 --position 0,0 -- --connect ws://127.0.0.1:8910 --look 2

# 3. Player two.
$godot --path game --resolution 960x540 --position 960,0 -- --connect ws://127.0.0.1:8910 --look 5
```

Both windows of one machine read the same saved look (`user://settings.cfg`), so without `--look` they would wear the
same one. `--look N` wears the preset N for this run only (it is sent to the server like a saved look, never saved);
`--look seed:N` wears a random look made from seed N. A look is sent once after joining; the server tells everyone
(a player who joins later is told everyone's), and every screen dresses each player, your own body included, from the
same table, so a player looks the same on every screen.

The first player to arrive starts the night; the second joins it where it is. Move with WASD and the mouse, shoot,
buy and repair as in single-player. Each window shows the other player (their own look and the armband of their
seat) walking, and the same zombies. The server prints one JSON line a game event (`joined`, `left`) and a `stats`
line every ten seconds.

Without the command line: start the game, choose **Join** on the main menu, type the address (the field starts at
`ws://localhost:8910`; `host` or `host:port` is enough) and press Join.

| Option after `--` | Meaning |
| --- | --- |
| `--server` | run a game server instead of the game (headless; no menu) |
| `--port N` | server: the port to listen on (else `$PORT`, which Railway sets, else 8910) |
| `--seed N` | server: the night's seed (else a new one for each night) |
| `--connect [URL]` | client: go from the menu straight into the night of that server (default `ws://localhost:8910`) |
| `--look N`, `--look seed:N` | client (and single-player): wear the preset N, or a random look from seed N, instead of the saved look |
| `--bot` | client: let the autopilot play this player (it uses the shoulder camera, like a person's) |

Port 9080 is not used: the Godot editor's MCP bridge listens there on the maintainer's machine, and Windows lets a
second listener bind it silently. Check a port with `netstat -ano | grep :8910`.

### A window and a bot

To see a player from the outside without a second person, add `--bot` to the second window:

```text
$godot --path game --resolution 960x540 --position 960,0 -- --connect ws://127.0.0.1:8910 --bot
```

The bot buys doors, repairs, switches the lights and shoots; it is the same autopilot that plays the balance
night, now over the network.

### Playing from another machine

Use the server machine's address instead of `127.0.0.1` (`ws://192.168.1.20:8910`) and allow port 8910 through its
firewall. A browser cannot reach a plain `ws://` server from an `https` page; that needs `wss://` (Railway's edge
gives it).

## What a test can do

The scenario suite `game/tests/net/test_night_online.gd` runs a server and clients over a real WebSocket in one
headless process: each of them lives in its own `SubViewport` world, so each has its own physics and navigation.

```text
$godot --headless --path game -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/net -c --ignoreHeadlessMode
```

It checks that two clients see each other walk (what one hears is what the server has), that each player's parts and
colours are the same on both clients and in the server's table, that each client's own body wears its saved look, that
a late joiner is told the looks already there and a new connection in a seat replaces the old look, that a player is
as tall (skeleton height and global scale, to a millimetre) on every client (the server has no model to measure), that
the zombies on every client are the server's and a shot is heard by both with the right shooter and paid to the right
player, that a player who joins in the middle gets the doors, the round and the points as they are, that a player who
leaves disappears for the others and the seat is reused, that a fifth player is turned away, and that a server nobody
is on gives a reason instead of a hang. `test_net_wire.gd` covers the bytes (a hostile command is made harmless) and
`test_night_commands.gd` the server's handling of commands.

`game/tests/captures/online_heights.tscn` renders two clients of one night side by side in one window, each with the
other player standing beside their own at the same lamp post (so the two screens show the same player's size, look and
facing together):

```text
$godot --path game res://tests/captures/online_heights.tscn --resolution 1280x720 -- --out=<abs>/heights.png
```

`test_world_parity.gd` holds that every solid thing a player can bump into (a `CollisionObject3D` or a colliding
`CSGShape3D` other than a body) is in the client's viewport and in the server's, at the same place. A view or a drawing
never adds collision of its own: the prize crane's cabinet did, only on the client, and a sprint past it ended 2.2 m
from the server's body (#748); the cabinet is now `CraneBlock` in `NightWorld`, moved by the rules on a server and by
the frame on a client.

The bodies are held to the same rule (#760): the client draws the other players as puppets that stop nobody, so a played
body sits on a physics layer of its own (`PhysicsLayers.BODY`, 4) that no body's mask lists, and the server's bodies pass
through each other. Every ray that met a body before (shots, the dead's swing, grenades, footsteps, a ping) lists the
layer in its own mask, so nothing but the bodies' collision with each other changed. They used to stop at one another on
the server alone (layer 1, mask 1 and 2): a sprint into a teammate or a bot ended the server's body in place while the
client's went on, and at the next corner of a car the two went round different sides, 2.5 m apart (the reconciler's
snap, so the soak's bound). `WorldSolids` lists the walls under a viewport; the bots-slots soak compares every client's
with the server's every 300 ticks, and its failure line says what each body last slid on.

To use a server in your own test: add a `NightHost` (`port = 0` picks a free port, read back from
`host.listener.port()`) and join with `Night.start_remote(url, Night.Mode.MANUAL)`; in `MANUAL` the test sends the
commands through `night.link`.

## A bad network, and the CI scenario

`LinkConditioner` puts a bad network between a client and its server: `WebSocketLink.conditioner_in` and
`conditioner_out` hold every packet back `delay` seconds (plus a random `jitter` either way), in order, as TCP delivers
them; a `stall_chance` of packets is held `stall` seconds longer with everything behind it (a retransmission: a
WebSocket cannot lose a packet, so loss is a stall here). A bot, a test or a window can use it.

`test_netcode_scenario.gd` is the run #56 asked for: a game server and two bots (the autopilot, each driving its own
predicted body from its own shoulder camera) over a real WebSocket with 100 ms each way, 20 ms jitter and 1 % stalls,
for twenty seconds. The first run on a loaded Windows machine: a round trip of 211 ms, the predicted bodies never more
than 0.89 m from the server's (a sprint's length in the round trip), the reconciler's worst error 0.89 m, 150 and 197
corrections in 20 s, and when the bots stop sending both bodies settle within 12 cm of the server's. The test fails on
more than 2.5 m of drift or snap, or when they do not settle; an engine error anywhere in it fails the CI job like any
other test (the job reads the log). It runs with the rest of `tests/net` in the `godot` job.

The scenario runs on **game time**, not wall time (#528). It once waited `20` and `8` wall-clock seconds while the
conditioners held packets for real milliseconds; on a starved CI runner the game got a fraction of the frames in that
time (a run there made 484 and 210 corrections where a quiet machine makes about 50 and 40) and the bodies did not
settle in the 8 s. Now the link's `clock` (`WebSocketLink.clock`, the real clock when empty) is the physics frame count
over the tick rate, every wait counts physics frames, and the same 20 s of bad network is the same frames at any speed.
Slowing every frame by 0, 40 and 100 ms gave the same worst gap (1.12 to 1.17 m), the same corrections (41 to 53) and a
round trip of 234 to 250 ms; before, a 100 ms slowdown moved the round trip to 382 ms and the corrections to 76.

## Numbers from a local run

One Windows machine, loopback, server and clients in one process (`test_the_numbers_of_a_run_are_small`):

- a **tick to a client** (every 2nd step, 30 a second) is about **220 bytes** with two players and four zombies, as a
  difference against the previous frame, compressed when large; about 6.6 KB/s down. A command up is a fixed
  **25 bytes** (47 before protocol 2), 60 a second, 1.5 KB/s.
- the **round trip** (client ping, server pong, read on the client's 60 Hz tick) is 2 to 18 ms on this loaded machine;
  it is the sum of two tick waits, not the network.

Bigger figures (more zombies, four players, the manual run's server log) are in [Multiplayer](multiplayer.md#the-real-game-over-websocket).

## What is not here yet

- **The Discord proxy.** The server is reached directly; through a Discord Activity it goes through Discord's proxy,
  which waits for the Activity setup ([#287](https://github.com/Ryubara/deadnight/issues/287)).
- The tighter packing of many zombies and projectiles
  ([#57](https://github.com/Ryubara/deadnight/issues/57)).
- The other players' repair and weapon animations are not drawn
  ([#245](https://github.com/Ryubara/deadnight/issues/245)).
