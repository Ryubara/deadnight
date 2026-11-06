# The arrival: a helicopter drop

Every player's arrival in a night is a short helicopter drop, on that player's own screen and nowhere else (issue 1057).
At the start of a night, and for anyone who joins late, a helicopter is heard far off, closing in; the picture
is a camera high over the lot looking down at an angle; the helicopter hovers over the player's spot with its lamp lit,
a rope pays out of its open door, and the player's Soldier, in their own look, slides down it; the screen fades to
black and the player is in the night. The night underneath never stops: the server does not wait for the show, and
no other client sees it.

![The drop on the drive-in lot: the helicopter comes in, hovers with its lamp lit, the Soldier slides down the rope](arrival-sheet.jpg)

## What plays, and for how long

| Beat | Opening a night (6.5 s) | A late join (3.8 s) |
| --- | --- | --- |
| Black to picture | 0.6 s | 0.6 s |
| The helicopter flies in from the left, banking, its lamp coming on | first 2.5 s | none: it is hovering already |
| The rope pays out of the door | a fifth of what is left | the same |
| The Soldier slides down the rope | about 2 s | about 1.8 s |
| He stands; the camera has come in to the landing | 0.4 s | 0.4 s |
| Picture to black, then the black comes away on the player's own body | 0.7 s, then 0.45 s | the same |

The picture is **letterboxed on purpose**: two black bars, each `ArrivalCutscene.BAR_SHARE` (7.5%) of the screen's
height (58 of 780 px on a phone page's 1688 x 780 canvas), over the whole show and the 0.45 s after it (the skip hint
sits in the lower bar). They come away with the show; a night in play has no bands. A capture taken in that 0.45 s, or
of a page that plays the show, shows them (Deadnight #1261: `night_phone_capture` now waits for the show to be gone).

The sound: a synthesised piston-engine rotor loop (ten beats a second, an engine under it, the tail rotor's whine)
that starts in the dark far away and closes in with the helicopter, as a 3D loop on the helicopter under the show's
camera, so distance does the rest; the rope's run through gloved hands; the boots on the lot. All three come from the
`arrival` sound bank, which is **on demand**: the night's loading bar and the background decode skip it, and nothing
loads it until a show plays (`SoundBank.on_demand`).

The model is ours: `tools/blender/build_helicopter.py` builds a 1,264-triangle utility helicopter (olive, a cream
stripe, an open door) from boxes and cylinders on one palette atlas, in the pinned Blender; the sounds are
`tools/audio/arrival_recipes.py`. The scene is made from `ArrivalPlan` (where everything is at each moment: pure, no
clock) and `ArrivalCutscene` (the nodes), built when the show begins and freed when it ends.

## How the player is protected

The server has to know, because the player's body is in the lot from the moment they join. The client says so
(`NetWire.ARRIVAL`, two bytes: the drop begins, the drop ends) and `ArrivalPlay` keeps the rules:

- from `begin` to `ends` (or `ArrivalTuning.cap_seconds`, the backstop for a client that stalls, closes or lies) the
  player **cannot be hurt** (`GameRules._blow` refuses every blow: a zombie's, a blast, the ray gun's splash), **is not
  chased** (the dead are not sent after them), **does not move or act** (the server ignores their commands, so a
  modified client cannot walk off invulnerable), and **is not drawn** by the other clients nor named by their markers;
  bots drop them from what they believe about the crew;
- after the landing a **grace** (`grace_seconds`) in which a blow still does nothing, while the controls are theirs;
- the shield is in the rules' snapshot (`drop_left`, `grace_left`, `dropped`), so a late joiner's WELCOME and a
  resumed client read it;
- **one drop a seat**: asking again protects nothing; a bot has none; a client that never sends the message (a bot's
  autopilot, a test) is never shielded; a player who comes back on a new socket (the resume) gets none.

The player is not counted down meanwhile (they are on their feet), and the night's clock, the rounds and the dead are
untouched by it. Nothing waits: the server steps at its own pace whatever the client does.

On their own screen the player's controls are off for the length of the show: the body is hidden, mouse look is
locked, and every command the client sends is neutral (the server ignores them anyway). The HUD, the reticle and the
touch layer give way and come back with the landing.

## Where the camera stands

The camera stands behind and above the spot, looking down about 40 degrees. A fixed offset put it behind the drive-in's
screen on the first try, so the show casts rays from the spot to each of twelve headings (nearest the preferred one
first) and takes the first from which nothing solid lies between the camera, the spot and the sky above it. On the
second map the roof and ceilings (`Ceilings`, `Roof`) are hidden for the show, and the rays ignore them, so the camera
looks into the depot from over its wall.

## Tuning

All of it is one table, `ArrivalTuning`, in `default_tuning.tres` (the rules' table, so the server and every client
read the same numbers):

| Setting | Default | What it does |
| --- | --- | --- |
| `enabled` | on | Off: nobody is dropped, and the server grants no shield |
| `night_seconds` | 6.5 | The length of the drop that opens a night |
| `late_seconds` | 3.8 | The length of a late join's drop (no fly-in) |
| `skippable`, `skip_after` | on, 1.0 s | Any key, pad button, click or tap skips it after this long (Esc does not) |
| `repeat` | `ALWAYS` | `FIRST_PER_SESSION` plays it once each time the game is opened |
| `grace_seconds` | 1.5 | Harmless seconds after the landing |
| `cap_seconds` | 12.0 | The most the server shields a player whose client never says it landed |
| `fade_in_seconds`, `fade_out_seconds` | 0.6, 0.7 | The black at both ends |
| `hover_height`, `camera_height`, `camera_back`, `camera_fov` | 14, 26, 24, 50 | The camera and the helicopter's height |
| `approach_distance`, `approach_share` | 70 m, 0.38 | How far the helicopter flies in from, and the share of the show it takes |
| `lamp_angle`, `lamp_range`, `lamp_energy`, `rotor_rps` | 24, 26, 6, 5.5 | The lamp and the rotor |

## What a person plays and what does not

A person's game turns the show on (`NightScreen.arrival_enabled`); a test, a capture and a bot never see it unless they
ask (`Night.arrival`). A headless run draws nothing and plays none. A page that asks for the probes (`WebProbe.asked`)
skips it too, so the web probes, which drive the night from its first frame, keep working; a probe page asks for it with
`?arrival`, and `?noarrival` turns it off for a person's page.

## Decisions for the maintainer

The three the issue names are tunable above, with these defaults recommended:

- **Length.** 6.5 s opening a night, 3.8 s for a late join. The opening runs under the intro break (12 s), so the player
  lands with about 5 s left of it; the late join has no fly-in, because a player joining a fight should not wait. If
  the opening feels long, shorten `night_seconds`; the intro break (`RoundTuning.intro_seconds`) is a separate number
  and the server does not wait for the show, so a longer drop is a shorter wait for the first round.
- **Skipping.** Yes, after 1 s: the first second is the helicopter coming in and the screen fading up, a press then
  fades out in a quarter second, and the server shield follows the client's word, not a timer, so a skip gives no free
  invulnerability. Off, the drop always plays in full.
- **Returning players.** Every join, the same: the late join's 3.8 s is short, and a returning player who finds it long
  has the skip. `FIRST_PER_SESSION` is one line if the maintainer prefers once a visit.
