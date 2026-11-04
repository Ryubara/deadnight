# The end of a night: research

What the genre does at the end of a match, what we found building ours, and the numbers. The design is
[the end of a night](../design/end-of-night.md) (Deadnight #973). The genre is the reference for feel only.

## What the genre does (public sources)

Searched 2026-11-04; the genre's own documentation says little about the staging, so these are what players, wikis and
trackers describe, and nothing here is copied:

- **Zombies modes** put the result on a still or slowly moving world: a "game over" line with the rounds survived at the
  top centre, the leaderboard under it, then the results screens, then the lobby, with the party's progress reset for the
  next run ([Black Ops, game over text and leaderboard](https://game-over-dex.fandom.com/wiki/Call_of_Duty:_Black_Ops);
  [Black Ops 6, "eliminated", rounds survived, results, then the lobby](https://game-over-dex.fandom.com/wiki/Call_of_Duty:_Black_Ops_6)).
  The newest ones add a short third-person collapse before the cut.
- **Multiplayer** ends on a camera that is not the player's: the final killcam, replaced in some titles by "best play",
  both a replay set up to be looked at, then the scoreboard
  ([Best Play replaces the final killcam](https://x.com/CODTracker/status/1303768700957454337);
  [the final killcam, with its quirks](https://gamefaqs.gamespot.com/boards/995751-call-of-duty-modern-warfare-3/61568440)).
- **The party** stays together through it: queuing and persistent lobbies exist so friends land in the same room again
  ([party queuing](https://www.sportskeeda.com/esports/news-warzone-2-modern-warfare-2-get-new-party-queuing-feature-find-competitive-teammates-easily)).
- **Not found in any source:** an official length for the intermission, or a Zombies camera that flies over the map.
  The maintainer's ask (a slow overview from the player's own camera, cuts between angles, the board over it, about
  15 s, the lobby kept) is the brief; the genre only says the beats exist (title, board, wait, lobby).

## Findings from building it

- **The server owns the end.** A night that ends on the client alone cannot keep every screen on the same second. The
  server stops stepping the night when the rules say `game_over` (the bodies, the dead, the weapons and the rules all
  stand where they were), counts `NightServer.END_SECONDS` (15) in its own step, and puts the whole seconds left in every
  frame (`over_left`, `-1` while the night is on, so a night in play pays nothing for it). At 0 it sends `night_closed`
  once. A client counts the end by that number, never by its own clock.
- **Old behaviour to remove: the client left the seat at the game over** (#467: its link stayed open and unread, and a
  browser logged "Buffer payload full"). It now stays and reads the frames (they cost nothing, the night is still), sends
  no more commands, and closes its link at `night_closed` or when its player presses Leave. The room waits for them for
  `NightHost.CLOSE_GRACE` (3 s) and then hangs up on the rest.
- **The lobby has to come back from the backend.** The backend dropped a lobby when the game server told it the match was
  over, and the lobby screen is replaced by the night when it starts, so nothing carried the host, the people, the map or
  the rules back. The game server now says `finished` with the users still present (`POST /internal/matches/:id/end`
  with `{finished, present}`); `LobbyService.matchEnded` reopens the lobby for them (state open, same code, host, Activity
  instance and settings) instead of removing it. Any other end (everyone left, a crash, a heartbeat that stopped
  listing the match) still drops it. A client asks for its lobby until it reads `open` (up to 10 s), then replaces the
  night with the lobby screen.
- **A player who leaves during the intermission** is an ordinary leave: the seat is freed, nothing else changes. If the
  night's clock has not run out, the board of the others keeps their row (the board remembers what it last heard). The
  leaver is also out of the lobby, so a host who leaves hands the role on.
- **The rounds column is the rounds a player stood at the end of**, from the new `standing` list of `round_ended`
  (taken before the end of the round gets the downed up). A player who joins late has fewer. The headshots column is
  headshot kills by a gun (a melee kill is not one, as the rules pay it).
- **A pull-back has to be swept.** The lens starts on the player's own camera and goes back and up; `EndCamera.pull_target`
  sweeps a sphere from the player to the wanted place and then from the lens to what it reached, the way the shoulder
  camera does ([camera page](https://github.com/Ryubara/gdstudio)), so a wall behind the player shortens it.

## The shots

Each map holds its angles in its resource (`end_shots`, `world/maps/drive_in.tres` and `small_indoor.tres`). Every angle
drifts a lens in a straight line while looking at a point (`EndShot`); the numbers are in metres of the map (x east, z
south) and are checked by `test_end_shots.gd` against the walls: the lens is never within 0.3 m of a solid along the
drift (26 rays from it, since a point in a concave CSG wall is not reported by an overlap test), the view is open for
1.5 m, a sphere swept along the drift is not stopped, and the look point is over the map. The pull-back from each of the
eight starts of each map is checked the same way.

- **The lot** is 120 m across and dark: the lens is 15 to 34 m up, outside the fences, so the walls never matter and
  the lamps, the beam and the screen carry the picture (the outer slab, `Outskirts`, shows beyond the fence at the
  bottom of a frame).
- **The back rooms** are closed shells, dark outside (the first outside angle showed fog and fence posts and nothing of
  the building), so all four angles are inside, at 2.5 m under a 3.2 m ceiling, in the hall (x 0 to 16, z 0 to 14.8)
  and the rewind room (x -6.3 to 16.3, z -8.1 to 0). A pillar at x 14.1 stood within 1.5 m of the first draft of the
  east rewind shot, which ran along z -4 (the row of pillars); the test caught it and the lens moved to z -1.4.
- Authoring: `tests/captures/end_shots_tour.tscn` renders a map from `--cam=name:x,y,z,tx,ty,tz[,fov[,near]]` or every
  authored shot at its start, middle and end; a near plane far out (`near` 56.4 from 60 m) cuts the roof away as a plan.
- The whole sequence on both maps, desktop and phone, is `tests/captures/end_sequence_tour.tscn` (the real night
  screen, the dead let loose, everyone down; it prints `closed after 150 frames`, the 15 s at 10 frames a second).

## Tests

`tests/night/test_end_camera.gd` (start on the lens, ease, walls, cuts, any frame rate),
`tests/world/test_end_shots.gd` (both maps), `tests/night/test_end_of_night.gd` (a solo night through the real
server: the stand-still, the clock 2, 1, 0, `night_closed` once, the counts in the frame),
`tests/rules/test_end_tally.gd`, `tests/ui/test_hud_end_board.gd` (rows, order, a leaver's row kept, five canvases and
a phone with its notch), `tests/ui/test_night_screen_end.gd` (the real Play and night screens to the end and back,
the rules kept), `tests/net/test_end_of_night_online.gd` (the real backend and game server: clocks in step, a leaver,
a host who leaves, a night everyone left, the night screen ending on the lobby screen with the rules),
`tests/net/test_game_over_link.gd` (the client stays through the intermission, then leaves and reads no more) and the
backend's `lifecycle.test.ts`.
