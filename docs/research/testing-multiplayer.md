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
   - **Quick join**: you land in a public night with room, or a new one starts.
   - **Create a night**: the screen shows a code and an invite link; **Copy the link** and send it. A friend who opens
     the link (`?room=CODE`) lands in your night at once, or types the code under **Join with the code**.
3. **Play** (after Create) or the join itself builds the lot and warms it up (about 35 s in Chrome with a graphics card).
   Up to four share a night, and a player who comes later joins it where it is.

Inside a Discord Activity the same page lands everyone of the voice channel in one night with no code
(`?instance_id=` from Discord).

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
invite link, C and D press Quick join) and fails unless each pair sees exactly two players:

```text
uv run --with playwright==1.64.1 python tools/web_smoke/rooms.py <web URL or build/web> <backend https address> <out folder> --gpu
```

`tools/web_smoke/online.py` joins one game server by its address (the developer path) and plays a night, reading the
page's probe (`players`, `alive`, `rtt_ms`) every second:

```text
uv run --with playwright==1.64.1 python tools/web_smoke/online.py <web URL or build/web> <server address> <out folder> --seconds 90 --gpu
```

## Two desktop windows on one machine

Open three terminals.

```text
# 1. The server: one night, up to four players. Headless, plain ws://, port 8910 unless told otherwise.
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
as tall (skeleton height and global scale, to a millimetre) on every client and on the server, that the zombies on
every client are the server's and a shot is heard by both with the right shooter and paid to the right player, that a
player who joins in the middle gets the doors, the round and the points as they are, that a player who leaves
disappears for the others and the seat is reused, that a fifth player is turned away, and that a server nobody is on
gives a reason instead of a hang. `test_net_wire.gd` covers the bytes (a hostile command is made harmless) and
`test_night_commands.gd` the server's handling of commands.

`game/tests/captures/online_heights.tscn` renders two clients of one night side by side in one window, each with the
other player standing beside their own at the same lamp post (so the two screens show the same player's size, look and
facing together):

```text
$godot --path game res://tests/captures/online_heights.tscn --resolution 1280x720 -- --out=<abs>/heights.png
```

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

## Numbers from a local run

One Windows machine, loopback, server and clients in one process (`test_the_numbers_of_a_run_are_small`):

- a **tick to a client** (every 2nd step, 30 a second) is about **220 bytes** with two players and four zombies, as a
  difference against the previous frame, compressed when large; about 6.6 KB/s down. A command up is a fixed
  **23 bytes** (47 before protocol 2), 60 a second, 1.4 KB/s.
- the **round trip** (client ping, server pong, read on the client's 60 Hz tick) is 2 to 18 ms on this loaded machine;
  it is the sum of two tick waits, not the network.

Bigger figures (more zombies, four players, the manual run's server log) are in [Multiplayer](multiplayer.md#the-real-game-over-websocket).

## What is not here yet

- **The Discord proxy.** The server is reached directly; through a Discord Activity it goes through Discord's proxy,
  which waits for the Activity setup ([#287](https://github.com/Ryubara/deadnight/issues/287)).
- Hit rewind
  ([#54](https://github.com/Ryubara/deadnight/issues/54)), the tighter packing of many zombies and projectiles
  ([#57](https://github.com/Ryubara/deadnight/issues/57)).
- The server's players still have bodies with models, and the other players' repair and weapon animations are not
  drawn ([#153](https://github.com/Ryubara/deadnight/issues/153), [#245](https://github.com/Ryubara/deadnight/issues/245)).
