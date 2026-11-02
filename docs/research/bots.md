# AI teammate bots

Research and plan, 2026-11-01, for the bots that fill empty player slots. Nothing here is built yet: the page says what
shipped games learned, what our own code already gives a bot and lacks, what to build, in what order, and how each
step is proven. The bot that exists today is the `Autopilot` (`game/gameplay/night/autopilot.gd`); the rules it plays
by are in [Rounds, points and fuel](../design/rounds.md), the wire in [Networking](../design/networking.md).

Numbers marked *proposal* are starting values to be measured and tuned, not facts. Numbers marked *measured* were taken
on this repository's `main` for this page (headless, a machine shared with other jobs, so read them as orders of
magnitude).

## The recommendation in one screen

- **A bot is a client.** It runs in the server process as a *virtual client*: it reads only a `ClientState` (the frames
  and events a person's client gets) and static level data, and it sends only `NightCommand`s through the same
  `NightServer.apply` a socket uses. No bot API, no peeking at `GameRules`, `ZombieSim` or `CombatServer`. A test
  proves it by replaying a bot's command stream into a fresh server and getting the same night.
- **Architecture: a hand-written behaviour tree** (a prioritised selector, in the Halo 2 sense) as the skeleton, with
  **utility scoring at the three places a choice is real**: which zombie to shoot, what to buy, which task to take.
  Not GOAP and not HTN: our action set is small and fixed, and planners cost more to test than they give.
  Plain `RefCounted` GDScript, no scene tree, no addon.
- **Perception is a filter in front of the brain**: a view cone, line of sight, light, hearing by events, a memory that
  fades, and a reaction queue. The brain never sees the raw frame.
- **Aim is a model, not a dice roll**: a reaction delay with a floor of 0.2 s, a spring-limited turn rate, tracking noise
  and fire cadence. Accuracy is what comes out; it is checked against the balance simulator's skill levels. Difficulty
  changes the *player model* (reaction, aim, discipline), never zombies, damage or points.
- **Revives are risk-assessed**: clear the zombies around the victim first, then go in, abort on a rule with hysteresis.
  A human is saved before a bot. The last bot standing survives to the round's end, because a downed player gets up
  then.
- **Never cheat to look good**: no teleport, no extra reach, no perfect aim; reflexes are projected onto the walking
  mesh so a bot never panics off a ledge. A stuck bot climbs a recovery ladder and reports itself.
- **Prove it in layers**: pure unit tests, about thirty named scenarios, a soak of whole nights with stuck metrics,
  telemetry, and a parity batch of bot nights against the balance simulator's human skill levels.
- **Cost**: the current bot's decision step measured 0.06 to 0.17 ms at 60 Hz with up to 40 zombies in view; the plan
  thinks at 10 Hz, so three bots should cost about 1% of a 30 Hz server tick ([Server cost](#server-cost)).
- **Eight phases (0 to 7)**, each with its own definition of done ([Phases](#phases)); the first is not bot work at all,
  it is the human actions a bot needs and the game does not have yet (revive, circuit switches, pings).

## What our code gives a bot, and what it lacks

| Piece | Where | What a bot gets from it |
| --- | --- | --- |
| `NightCommand` | `gameplay/night/night_command.gd` | The whole input of one tick as plain data: `PlayerCommand` (move, yaw, pitch, sprint, crouch, jump, aim, throw), `fire`, `reload`, `use`, `swap`, camera `origin`, `dir`, `muzzle`. A person and the bot send exactly this. |
| `NightServer.apply` | `night_server.gd` | One entry for `join`, `leave`, `start_night` and `command`; the latest command per player is used; `reload`, `use`, `swap` are edges used once. |
| `ClientState` | `client_state.gd` | Frames (players with position, facing, health, downed, weapon, ammo, reserve, points, `prompt`; zombies as `ZombieCodec` bytes; doors, boards, fuel, phase) and events. It reads no game object. |
| `use_target` / `prompt` | `night_server.gd` | What `use` would do now: a door (with price), a breach with a board down, and (#214, open when this was written) wall weapons, ammunition lockers and the crane. The bot reads it as a human reads the prompt. |
| `RulesAction` | `rules/rules_action.gd` | The only way to change the night; validated by one schema. Bots never send these: the server turns commands into them. |
| Autopilot | `night/autopilot.gd` | Moves with the navigation mesh, backs away inside 7 m, shoots the nearest zombie in sight (camera and barrel both clear), reloads, buys the next door, repairs boards. Plays five rounds alive (measured below). |
| Zombie navigation | `zombies/navmesh_baker.gd` | One mesh (cell 0.25, agent radius 0.5, height 1.75, climb 0.25, slope 45 degrees); rebaked when a door opens. The bot uses `NavigationServer3D.map_get_path` on it. |
| Balance simulator | `tools/balance/` | `SimSkill` levels (weak, average, strong) with accuracy 0.45 / 0.65 / 0.82, head rate 0.06 / 0.15 / 0.30, dodge, read; the reference for "like a human". |

### Gaps a bot would meet (each is a phase item)

**1. A shot's direction is not tied to the view.** `NightServer._shoot` takes `command.dir` as sent, and the Autopilot
   sets the camera ray at the target while its `yaw` is where it walks. A person's `dir` is the camera's forward, so
   they can only shoot where they look. A bot that shoots one way and walks another is superhuman, and the same hole is
   an anti-cheat hole for clients. Fix: the bot derives `dir` from its own yaw and pitch
   (`NightCommand.aim_along`, the same basis as the camera rig), and the server refuses a shot whose
   `dir` is more than `NightTuning.aim_slack_degrees` (10) off `motion.yaw/pitch` (*closed by Phase
   0*; a person's camera measured under 1 degree off).
**2. No turn-rate limit on the server**: `yaw` may jump any angle in a tick. The bot must limit itself.
**3. No revive.** *Closed by Phase 0 (#224).* There is now a `revive` rules action, a channel on the held `use`
   button beside a downed teammate, and no bleed-out: a downed player waits to be raised or for the round's end.
**4. No circuit switches in the lot** (#206), **no fuel purchase spot** (the shop item exists, `use_target` offers
   none), **tonics do nothing**.
**5. Crouch is carried and not acted on** (#73); **no step up of low ledges** (#78); the jump is 1.1 m.
**6. No pings or callouts.** *Pings closed by Phase 0 (#224); callouts are Phase 5.* World markers and teammate
   names landed with #430.
**7. The night is one player**: `Night` joins `PLAYER_ID = 1`. `NightServer` already takes any number of `join`s, so
   scenario tests can seat four; the networked match is #53 to #57.
**8. The frame carries every zombie in the lot**, as it does for a person's client. Interest management is #57; until
   then the bot's own perception filter is the only thing between it and a wallhack.

## What shipped games did

Sources are linked in each row; the full list is at the end. "Read" means I read the text myself (the slides and the Game
AI Pro chapters, extracted from their PDFs). "Fetched" means a web page read through a summarising fetch, so quotation
marks on this page are only used where the summary quoted the page; check a line against the page before reusing it.
"Reported" means I know it only from a search summary of a patch note, forum thread or review.

| Game | What it did | What we take from it |
| --- | --- | --- |
| Left 4 Dead | Bots fill empty survivor slots. The Director paces the team by an "intensity" per survivor: damage, incapacitation and nearby kills raise it, it decays unless zombies are engaged, and a relax period follows a peak ([Booth, GDC 2009](https://cdn.fastly.steamstatic.com/apps/valve/2009/GDC2009_ReplayableCooperativeGameDesign_Left4Dead.pdf), read). The navigation mesh came from the Counter-Strike bot and answers "has this area been seen" and "flow distance". | The team is one unit that the Director tunes; a bot slot must not change the pacing logic, only the number of players. A nav mesh with annotations is the shared base for bots and zombies. |
| L4D survivor bots | Community fixes list what the shipped bots got wrong: heal or take pills while a teammate is incapacitated or pinned, keep rescuing after the teammate is fine, give up a revive on the first infected hit, retreat from a Charger busy with another survivor, walk into acid and fire, move left and right repeatedly when they cannot path, fail to jump on ledges ([Improved Survivor Bots](https://github.com/justin-chellah/improved-survivor-bots), fetched; abandoned by its author). | A list of failure modes to test one by one ([Failure modes](#failure-modes-and-how-each-is-avoided)). |
| Counter-Strike bots | Booth made the original bot; skill is a profile of numbers: `ReactionTime` 1.00 / 0.80 / 0.45 / 0.22 s and `Aggression`, `AimFocus*` (an aim error that shrinks while on target), look-angle stiffness and damping ([BotProfile.db](https://gist.github.com/so0k/7505931), a community copy, fetched; [GDC 2004 talk on the bot](https://www.gamedeveloper.com/design/gdc-vault-adds-valve-biofeedback-i-counter-strike-i-i-half-life-2-i-talks), reported). | Difficulty as a data profile, with an aim-error model and a spring on the view angles. |
| Valve NextBot | A bot is a Behaviour made of Actions, with factors such as Locomotion and Intention; code is in the Source SDK 2013 ([Valve wiki](https://developer.valvesoftware.com/wiki/NextBot), reported; the page itself refused my fetch). | Locomotion, perception and decision are separate parts; "stuck" is the locomotion's business. |
| Vermintide 2 | Bots "run the same code as players but control their character through virtual key presses on a virtual controller", simulate aiming so as to avoid faster-than-human reaction shots, rely on timed danger areas to dodge, assign each bot a *follow point* from the player's predicted position, and teleport when stuck, their only cheat. Admitted problems: stuck bots, hordes, bosses ([Fatshark dev blog](https://www.vermintide.com/news/2018/12/17/dev-blog-how-bots-work-in-vermintide-2), fetched). Patch 4.2 added navigation-mesh cost weights for hazards, less "panicky" emergency steering because the old one had been making bots slip off cliffs, fewer horde charges, and a restriction on bots taking ammunition and potions ([4.2 blog](https://www.vermintide.com/news/dev-blog-bots-in-42), fetched). Reported: healing at 40% instead of 50% ([patch summary](https://www.player.one/warhammer-patch-42-bot-improvements-general-fixes-and-more-139082)); "a suicidal drive to chase after specials with melee weapons"; bots still ignore revives sometimes ([Fatshark forum](https://forums.fatsharkgames.com/t/about-bots-again/45239/98)); stuck and falling off ledges ([thread](https://forums.fatsharkgames.com/t/bugs-with-bots-pathing-getting-stuck-falling-off-ledges/31245)). | The closest model of what we want: virtual controller, simulated aim, follow points. Their lessons: reflexes must stay on the mesh, bots must not hog the team's resources, and a leash stops suicidal chases. |
| Back 4 Blood | Reported: bots group too close together, always run to a downed player even when thinning the horde would be better, follow only the player who rushes ahead, risk trapping and falling off ledges, ping enemies and items; players ask for ping as a command ([Game Revolution](https://www.gamerevolution.com/?p=695027), [Pure Xbox on the developers' promise](https://www.purexbox.com/news/2021/08/back_4_blood_dev_confirms_bots_and_difficulty_balance_will_be_improved_for_launch)). No design write-up found. | Follow the group, not the leader in front; do not clump; make a revive conditional. |
| Toxic Commando | A zombie co-op shooter; player requests for its bots (admin marked "implemented" in a patch): react faster, clear the zombies attacking a downed player before reviving, heal at 50 to 60% health, use abilities, repair objectives, a longer downed timer ([Focus feedback board](https://community.focus-entmt.com/focus-entertainment/toxic-commando/ideas/15797-%F0%9F%A4%96-suggestions-to-improve-bots-greatly-benefits-solo-players), fetched). | The exact revive and objective failures players of a zombie game name. |
| Killing Floor | No built-in bots; a mutator adds them, and its comments report bots that do no melee damage, do not weld and do not follow objectives ([Workshop comments](https://steamcommunity.com/sharedfiles/filedetails/comments/1350604221), reported). | Capability coverage: a bot that cannot do a job a human does (weld, repair) is noticed. |
| Call of Duty Zombies | No shipped bots that I could find. The community's bots are multiplayer mods: Bot Warfare for Plutonium T6 has a `bots_skill` 0 to 3 and switches for grenades, jump-shots and aim ([README](https://github.com/ineedbots/t6_bot_warfare), fetched; it does not mention Zombies). A search summary described a BO2 Zombies bot mod that lowers the revive danger threshold for players without a perk (4 zombies instead of 8); I could not open the page, so it is unverified and not used. | The community's ask is revive judgement and door buying; no source to copy. |
| Deep Rock Galactic (Bosco) | A drone: it revives a downed player automatically, can be called with a shout, shows its revive charges, drops what it is doing to help, cannot revive in a moving drillevator; its AI cannot use explosive rockets so the player aims them ([wiki](https://deeprockgalactic.wiki.gg/wiki/Bosco), reported). | A limited, visible, predictable helper is accepted. Revive charges are a way to bound a helper; ours is a full player, so we bound it by risk rules. |
| Warframe companions | Forum reports: companions run off, attack what they cannot kill and die far away; DE chose to keep them "alive or with you at all costs" and hovering was meant to reduce pathing problems ([forum](https://forums.warframe.com/topic/1255114-companion-ai-is-broken/), reported). Valheim: no source found. | Close and alive beats clever. |
| Overwatch and Valorant practice bots | Fixed tiers; Riot changed their movement without patch notes, players ask for less predictable movement so aim practice means something ([Dot Esports](https://dotesports.com/valorant/news/riot-silently-updated-valorants-practice-bots-but-now-theyre-out-of-control), reported). No design interviews found. | A predictable bot gets exploited or gamed; keep the model's noise seeded but varied. |
| The Last of Us (Ellie) | The best-documented buddy: keep her *close*; follow positions rated every frame (distance, same side, not in front, distance to other buddies); no teleporting ever; she does not dodge until the last second; she "wants to not shoot" until the player fires; her damage was left as the player's but hits were made not to land when the player would not see them; gifting and throws on long timers; buddies invisible to enemies in stealth because a buddy that gives the player away breaks trust ([Game AI Pro 2, ch. 35](http://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter35_Ellie_Buddy_AI_in_The_Last_of_Us.pdf), read). | Follow design, no teleport, long cooldowns on anything noticeable, balance by leaving the buddy a human-sized share. We do not copy "damage that does not land": it breaks scoring. |

## Architecture: behaviour tree with utility scoring

| Option | For | Against | Verdict |
| --- | --- | --- | --- |
| Finite or hierarchical state machine | Simple, the Autopilot is one | "Transition overload"; every new job touches every state ([Game AI Pro 1, ch. 4](http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter04_Behavior_Selection_Algorithms.pdf)) | Too brittle for ten jobs; used only inside the motor (stuck ladder). |
| **Behaviour tree** (prioritised selector) | Stateless nodes that do not know each other; a priority list makes decisions easier to reason about and reduces dithering; Halo 2 shipped about 50 behaviours this way ([Isla, GDC 2005](https://www.gamedeveloper.com/programming/gdc-2005-proceeding-handling-complexity-in-the-i-halo-2-i-ai)); readable by a designer and an agent; cheap; trivially seeded and replayed | Numeric trade-offs ("buy or fight") are awkward as booleans; trees grow tall | **The skeleton.** |
| **Utility scoring** | Response curves turn "how much do I want this" into a number; good for choices among many similar items ([Game AI Pro 1, ch. 9](http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter09_An_Introduction_to_Utility_Theory.pdf); [Dave Mark and Kevin Dill, GDC 2010](https://gdcvault.com/play/1012410/Improving-AI-Decision-Modeling-Through)); can sit inside a tree ([Game AI Pro 1, ch. 10](http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter10_Building_Utility_Decisions_into_Your_Existing_Behavior_Tree.pdf)) | "Often somewhat unpredictable" ([ch. 4](http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter04_Behavior_Selection_Algorithms.pdf)); curves are tuning work; hard to say why it chose | **Only at three choice points** (target, purchase, task), with a commitment bonus so it does not dither. |
| GOAP | Emergent plans from small actions; F.E.A.R. used A* over actions with three FSM states ([Orkin, GDC 2006](https://pages.cs.wisc.edu/~dyer/cs540/handouts/gdc2006_orkin_jeff_fear.pdf)) | Plan search per agent per replan, plans nobody wrote are plans nobody tested; our jobs are few and fixed | No. |
| HTN | Hierarchical tasks with methods and conditions; Transformers' HTN was "considerably faster" than the studio's GOAP; partial plans defer cost ([Game AI Pro 1, ch. 12](http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter12_Exploring_HTN_Planners_through_Example.pdf)) | A domain to write and a replanner to debug ("the debugging headache you just created with your multiple planners") | No: our "plan" is the door order, a data list. Revisit if shopping gets multi-step. |

**Pitfalls to avoid from the tree literature** ([Game AI Pro 3, ch. 9](http://www.gameaipro.com/GameAIPro3/GameAIPro3_Chapter09_Overcoming_Pitfalls_in_Behavior_Tree_Design.pdf)):
one kind of node ("tasks all the way down"), no condition language written before it is needed, no blackboard as a
principle (a plain dictionary of beliefs is enough).

**Engines and addons.** LimboAI is a C++ behaviour tree and state machine plugin with a GDScript API and a debugger
([repository](https://github.com/limbonaut/limboai)); sources disagree about the Godot version it supports and I
found no benchmark. A GDExtension or custom module on a web export and a headless server is a risk we do not need: the
tree is about 300 lines, and the project's rule is that systems stay `RefCounted` data in, data out
([rules engine](rules-engine.md)). Beehave and similar addons are node-based, which a server without a scene tree
does not want.

### Structure

```text
 NightServer.apply(command)  <----  people's sockets
        ^
        |  NightCommand.to_dict()  (same validation, same rate limit)
   BotClient (one per empty slot; owns a BotProfile and a seeded RandomNumberGenerator)
        |
        +-- ClientState  (frames + an allow-list of events; nothing else)
        +-- BotPerception   filter: cone, light, line of sight, hearing, memory, reaction queue
        +-- BotBeliefs      plain dictionary: known zombies, teammates, goals, claims
        +-- BotBrain        behaviour tree, ticked at the think rate; utility choosers at 3 nodes
        +-- BotMotor        every tick: path following, steering, stuck ladder, aim spring, trigger
        +-- BotTelemetry    counters and a ring buffer of the last decisions
```

Top of the tree, in priority order (an interrupt may come from any higher rung):

**1. Reflex**: dodge a telegraphed blow or a blast area; step out of the boss's arc; leave a pinned position.
**2. Rescue**: revive a downed teammate when the risk check passes, or clear the zombies around them first.
**3. Fight**: pick a target (utility), choose and manage the weapon, reload at a safe moment, throw a grenade.
**4. Maintain**: ammunition, a swap to melee when dry, a safe place to reload.
**5. Errands** (utility chooser): door, wall weapon, crane, ammunition, fuel, circuit, repair a breach.
**6. Follow**: take a rated follow position near the humans.
**7. Idle**: hold, look around now and then, glance at the nearest breach.

## Perception: what a bot is allowed to know

A person on a screen knows what is on the screen, what they heard, what the HUD says and what they remember. The bot
is given exactly that, and the filter is a class of its own so a test can prove it.

| Knowledge | Rule |
| --- | --- |
| **Zombies** | Known only when inside a horizontal view cone (proposal: 110 degrees around the bot's own *aim* yaw, since the camera follows the aim), inside the sight range, with a clear ray from the eye to the head or chest. The sight range follows the light, as the simulator already models (8 m unlit, up to 33 m in full light: `VIEW_MIN`, `VIEW_PER_LIGHT` in `tools/balance/night_sim.gd`), read from the same lit-ground function the lamps use. |
| **Unseen but near** | Hearing: a zombie within 4 m and out of sight gives a *bearing and a range class* (near, very near), not a position; a landed blow gives the bearing the rules already send (`player_hurt` with `bearing`). The bot turns toward it, which costs a reaction time. |
| **Memory** | A seen zombie is remembered with its last position and velocity for up to 3 s (proposal), then forgotten; a remembered zombie is *never shot at*, only avoided and looked toward. This is the fix for Unreal's "never forgets" trap, where `Max Age` of 0 means a stimulus never expires ([AISenseConfig_Sight](https://dev.epicgames.com/documentation/en-us/unreal-engine/python-api/class/AISenseConfig_Sight)). |
| **Teammates** | Always known (position, health, downed, weapon): the HUD shows them and world markers are planned (#134). |
| **Level** | Doors, prices, breach positions, shop spots and the navigation mesh are static data every client has. |
| **Events** | An allow-list: what the feed and HUD already show (purchases, rounds, downs, own damage, boards torn or repaired, special round announced). `zombie_spawn_requested` and anything with server-side detail are dropped before the brain. The allow-list is a constant and a test asserts the dropped types. |
| **Never** | `GameRules`, `ZombieSim`, `CombatServer`, a zombie's health or exact spawn timing, other players' points beyond what the HUD prints. |

**Reaction queue.** A zombie that becomes visible enters the beliefs only after its reaction delay
([Aim](#aim-and-difficulty)); a threat appearing at the screen edge costs a turn on top.

**Wallhack tests** (Phase 1): a zombie behind a solid wall at 4 m, bot facing away, 600 ticks: it never enters beliefs,
and its aim is never within 10 degrees of it for longer than chance explains; a zombie that steps from behind a car
enters beliefs no sooner than the reaction delay after the first clear ray. A source scan test fails the build if the
bot code names `GameRules`, `ZombieSim`, `CombatServer` or `NightServer` other than the one `apply` callable it is
given.

## Aim and difficulty

Studies put simple visual reaction near 200 to 250 ms (mean 208 to 224 ms in a small study, [PMC6916673](https://pmc.ncbi.nlm.nih.gov/articles/PMC6916673);
a large click test's median is closer to 270 ms), and shooter bots are traditionally handicapped by "a timed reaction
delay or a random perturbation to its aim" ([Glavin and Madden](https://arxiv.org/abs/1806.05554)). Counter-Strike's
hardest shipped profile reacts in 0.22 s. Our floor is 0.20 s and no profile goes below it.

**The model** (all in `BotMotor`, all seeded):

**1. Acquire**: a new contact is believed after `reaction`, drawn per contact from a log-normal around the profile mean
   (coefficient of variation 0.2), clamped to at least 0.20 s. Switching to the next zombie after a kill costs
   `retarget` (0.12 to 0.25 s), a flick, not a snap.
**2. Turn**: the aim yaw and pitch follow the target through a critically damped spring (the CS profile's
   stiffness and damping) with a **maximum angular speed** per profile; the command's `yaw` and `pitch` are the spring's
   output and `dir` is derived from them (gap 1 above).
**3. Track error**: filtered seeded noise added to the aim, in degrees, scaled by the target's angular speed, the
   distance, the bot's own speed (sprinting aims badly) and the time on target (Counter-Strike's `AimFocus`: error
   shrinks while on target and decays when it leaves).
**4. Point of aim**: chest by default, head only at acquisition time with the profile's head-aim rate and when the
   target is slow and near enough for the weapon's spread; a crawler's low body and the boss's lit bulb are aim points
   from the look and type data the HUD already has (`ZombieModels.aim_scale`, the headliner's `weak` zone).
**5. Trigger**: fires when the aim error is inside the weapon's cone, plus a small rate of "panic" shots off target;
   cadence is the weapon interval plus a profile jitter (semi-automatic), or bursts of 3 to 5 (automatic); never a
   perfectly held trigger at the weapon's limit.
**6. Reload and swap**: tactical reload when the magazine is under 30% and no zombie is within 8 m; forced reload
   when dry; a swap to the best weapon *with ammunition* (sustained damage a second, the same ranking the simulator
   uses), melee when everything is dry.

**Profiles** (a `BotProfile` resource, about 25 named fields, no per-level code):

| | Rookie | Regular | Veteran |
| --- | ---: | ---: | ---: |
| Reaction to a new contact (s) | 0.55 | 0.35 | 0.25 |
| Maximum aim speed (degrees a second) | 240 | 360 | 540 |
| Track error at 15 m (degrees, 1 sigma) | 3.0 | 1.8 | 1.0 |
| Head-aim rate | 0.05 | 0.12 | 0.20 |
| Fire jitter (s) | 0.15 | 0.08 | 0.04 |
| Think rate (Hz) | 5 | 8 | 10 |
| Retreat early (metres of margin) | 5 | 7 | 9 |
| Revive eagerness (risk it accepts) | low | medium | medium |

*Proposal.* Calibration target: a profile's measured hit rate, head share and dodge land inside the corresponding
`SimSkill` (weak 0.45 / 0.06, average 0.65 / 0.15, strong 0.82 / 0.30) so the simulator and the bots tell the same
story; the profile numbers move to meet it, the simulator's do not.

**What difficulty never touches**: zombie health, speed or count, damage dealt or taken, points earned, ammunition. Ellie
taught the same: leave damage alone, "that makes an NPC feel broken". Accuracy is **emergent** from the aim model and
the weapon's own spread; there are no scripted misses, so a bot that misses is one a person could have been.

**Tests**: with a fixed seed, over 1,000 contacts the first-shot latency has no value under 0.20 s plus one tick; the
view angle's speed never exceeds the profile cap in any 100 ms window; the hit rate per profile lies in its band;
the same seed gives the same shots.

## Movement

| Concern | Design |
| --- | --- |
| **Paths** | `NavigationServer3D.map_get_path` on the zombie mesh (radius 0.5 covers the 0.35 m capsule), at most 3 Hz per bot, cached, followed with a look-ahead point more than 0.8 m away (the Autopilot's way), re-queried when the goal changes or the bot is more than 1.5 m off the path. The Godot guide warns that re-querying every frame makes an agent oscillate and that you must not read the next point after the path ends ([navigation agents](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationagents.html)). The measured cost of one lot-crossing query is 0.23 ms, the largest single item of the bot, so 3 Hz is a budget. |
| **No agent nodes, no RVO** | Like the zombie sim: direct server calls, no `NavigationAgent3D`. RVO avoidance ignores physics and meshes and can fail on head-on agents (same guide); the zombies' deterministic spatial-hash push is the model, and bots steer by their own rules. |
| **Door rebakes** | A bought door rebakes the mesh. On `door_opened` the bot drops cached paths and waits while the lot's bake is running. A path query before the map has synchronised returns nothing and prints an error (the [lesson of 2026-11-01](../lessons/2026-11-01-a-navigation-region-or-link-reaches-path-queries-after-a-few.md)), and a query to an unreachable point can print "not expect to not find the most reachable polygons"; so the bot asks `map_get_closest_point` for the goal first and marks a goal *unreachable* for 5 s when a query returns empty. |
| **Reflex movement stays on the mesh** | A dodge or a retreat picks among 12 headings, scores each (progress, clearance from zombies by type, light, loop room) and projects the end point onto the mesh. Vermintide's "panicky" emergency steering slipped bots off cliffs; ours cannot leave the mesh. |
| **Kiting** | Away from the nearest threats with a pull toward a loop (the lot's loops are in [the map](../design/map.md#loops-for-kiting)). Runners are 1.7 times faster; against them the bot holds a choke or a wall and fights instead of running (see [Edge cases](#edge-cases)). |
| **Staying near humans** | After Ellie: a *follow region* around the group (centroid of the humans, weighted toward the one who needs help), candidate positions by nav rays, rated each think by distance (3 to 7 m in a fight, 4 to 10 m outside), the same side as the leader, not in front, at least 2.5 m from other bots, in light, not at a breach, and outside the leader's firing cone. Allowed to arrive "close enough"; no pass through the leader. Vermintide assigns follow points so each bot takes the cheapest one. |
| **Not blocking** | Never stop inside a door gap or the 2 m passages (the map names them); if a human moves toward the bot and closes inside 1.2 m, step sideways at the last moment (Ellie's dodge). Keep out of a human's line to the nearest zombie. |
| **Ledges and jumps** | The mesh stops at a 0.25 m climb, so the bot never paths off an edge. It jumps only on curated `BotLink` markers (a car roof, the booth edge) and as the third rung of the stuck ladder. Until #78 lands it does not mantle. The booth's east drop (3.6 m) is a way down that costs health once fall damage exists; the bot treats it as a hazard unless it is escaping. |
| **Crouch** | Not used until #73 gives it an effect; then only for stationary aimed fire if the sim shows a benefit. |

### Stuck detection and recovery

Valve's NextBot has stuck as a locomotion concept, Unity's game crawler flags "no progress" as stuck
([GameCrawler](https://docs.unity3d.com/Packages/com.unity.automated-testing@0.7/manual/GameCrawler.html)), Vermintide
teleports its bots. Ellie never teleports ([ch. 35](http://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter35_Ellie_Buddy_AI_in_The_Last_of_Us.pdf)).
We do not teleport in v1.

**Stuck** means the commanded speed is above 1 m/s and progress along the path (not displacement) is under
0.25 m/s for 0.5 s. The ladder, one rung per 1.5 s without progress:

1. Sidestep 0.6 s to alternating sides (the Autopilot does this today).
2. Repath from scratch from the nearest mesh point, to a goal jittered by the bot's seeded stream.
3. Jump while moving, sprint if no zombie is within 4 m.
4. Drop the goal: mark it blocked for 10 s and take the next errand or follow a human.
5. Walk back along a breadcrumb trail (last 10 positions where progress was good).
6. Emit `bot_stuck` (position, goal, path, last 20 decisions) and keep following humans. At 20 s a soak test fails.

`stuck_seconds`, `longest_stuck_episode` and `ladder_depth` are first-class metrics ([Testing](#how-to-test-bots-so-they-are-not-buggy)).

## Economy

The bot knows the shop table (prices, prerequisites, plan order) because every client has it. It shops from the
`prompt` it is shown, like a person, and treats a refusal (`BuyResult`) as information, not an error.

**Ranking** (a utility chooser; each candidate scores need, affordability after the reserve, and distance, with a bonus
for the choice it made last time so it does not dither):

| Need | When it scores high | Notes |
| --- | --- | --- |
| Ammunition for the held weapon | Reserve under one magazine, points over the price | Never when the refill is below 10% of the reserve cap (the rules refuse `AMMO_FULL`); never mid-fight. |
| Fuel | Tank under 25% and rising draw, a can affordable | The can costs 100 plus 20 a round for 25 units; one bot at a time goes. Needs a fuel spot (Phase 0). |
| The next door in plan order | Points over the price and no human is closer to claiming it | See *door etiquette*. |
| A wall weapon not yet carried | Points over the price plus reserve, weapon ranks above the carried best | A weapon already owned turns its wall into an ammunition seller (#214, open when this was written). |
| The crane | Points over 500 plus reserve, fewer than three weapons, nothing else scored | A random prize the player lacks; no value if all are owned. |
| Grenades | Under two carried, points to spare | Two for 150 plus 5 a round, up to five. |
| Tonics | Only when they have an effect | They do nothing today, so the bot never buys one (the simulator does the same). |

**Reserve.** Keep one ammunition refill for the best carried weapon, plus one fuel can from round 3. Below the reserve
only a refill or a can is bought.

**Door etiquette** (the shop is per player, doors open for everyone, so two failures exist: nobody buys, or the bot
spends a human's savings target):

- Buy the next door when the bot holds the price **and** no human within 15 m of the door holds it too, **or** the bot
  has held it for 20 s.
- Prefer a break over a wave: in a round only when five or fewer zombies remain.
- Defer 10 s to a human ping on that door or to a human standing at it.
- Never buy a door while any teammate is under half health or downed.

**Sharing and not wasting.** Points cannot be given (`grant_points` is server-only), so a bot "shares" by buying team
goods (doors, fuel, repair) before personal power, and by *kill courtesy*: it does not shoot a zombie that is nearer a
human than to itself and closer to that human than twice the bot's range, unless the human is hurt, and it holds its
kill share near its fair share of the team (a metric, tuned in Phase 7). It never buys what the rules would refuse, a
rejected item backs off 30 s, and spending is capped so that points never sit above twice the next purchase for more
than a round (the "points glut" in [rounds](../design/rounds.md#open-questions) then goes to ammunition and
grenades, not to a hoard).

**Repairs.** Boards pay 12 each, at most 120 from one round's end to the next, so the pay is a shared purse. The bot
repairs in a break when no human is within 10 m of that breach and a board is missing, nearest first, and never while a
zombie is at the boards ("a zombie in reach strikes through the boards").

**Generator and circuits.** Keep `screen_lot` on; switch another circuit on only when a human is in its area and the
tank is over 40%, and off again when everyone leaves; it burns 0.05 to 0.08 a second a circuit and grows 3% a round
([rounds](../design/rounds.md)). Needs the switches (#206).

## Revives

No revive exists yet (Phase 0). When it does, these are the rules.

**Priority.** A downed human before a downed bot; among equals the one with the least time left; the nearest bot
claims (a shared claim table with a 3 s lease, ties by slot id), the others become *cover*.

**Risk check** (before committing, and again every think while reviving). Let `T` be the revive time (6 s in the
simulator). For each known zombie estimate the time to reach the victim, path distance over speed. The revive is safe
when no zombie can reach victim or reviver within `T` plus a margin, or when the bot can kill the ones that can in the
time it takes them (their health from the round's public formula over the held weapon's sustained damage, the numbers
the simulator uses). Unsafe: go to *clear*.

**Clear.** Fight from a place with a line to the victim's surroundings, with a target bonus for zombies nearest the
victim; throw a grenade or fire the flare only when the victim is at least 4 m from the blast (the blast is 3 m, and a
grenade hurts a downed player 40%). This is what Toxic Commando's players ask for, and what Back 4 Blood's "always runs
to the downed player" bots skip.

**Commit and abort.** Abort when more than one attacker is on the bot and it has lost 20 health in a second, or its
health is under 30%; but once progress passes 60% abort only under 30% health. A bot that aborts goes to clear
and retries. Hysteresis fixes both failures players report: "give up too easily" (L4D) and "die reviving" (B4B).

**Last standing.** Downed players get up at the round's end minus a tenth of their points, and the night ends when
everyone is down. So the last bot with humans down revives only if the risk check passes, else it kites to survive to
the end of the round, and it does not hold back from a revive that is safe.

**A downed bot** waits for a human: it does not crawl (no mechanic), and its callout fires once.

## Team roles and communication

**Roles are stances, not classes**, reassigned by utility every few seconds and sticky for at least 10 s:

- **Anchor** (default): within 6 m of the nearest human group; at least one bot is an anchor for each human.
- **Flank**: with two or more bots, one holds a choke 8 to 14 m on the other side of the group's heading.
- **Maintainer**: one bot at a time goes on an errand (repair, fuel, buy), only when no zombie is within 12 m and no
  teammate is hurt; it comes back.

Back 4 Blood's "follow only the one who rushes ahead" and Vermintide's follow-point assignment are the two ends: the
bot follows the *group's* centroid, weighted toward whoever needs aid.

**Callouts** are an enumerated event, `bot_say` (bot, line id, subject, optional position), shown in the feed and
later voiced. Lines: reviving, need ammo, reloading, door bought, low fuel, boss coming, runners, breach open, cover
me, thanks. Each line has a cooldown (20 to 60 s) and a global one per bot (4 s): Ellie's gifting and throws are on
"really long timers" because a repeated gesture stops meaning anything, and Back 4 Blood's bots "ping" constantly. A
bot calls out only what it *perceived*; a test checks that no line names an unseen zombie.

**Pings from people** (a new message, with the markers of #134): a location ("go and hold here" for 20 s), a door
("buy it" when affordable), an ammunition spot, an enemy (target bonus), a downed player (revive priority). Players
asked Back 4 Blood for ping-as-command; Vermintide's tagging was ruled out for tomes because "one tag could mean many
things", so the set is small and each ping has one meaning.

## Edge cases

| Case | Behaviour |
| --- | --- |
| **Boss night** (15 times a walker's health, +100% per extra player, a 1.2 s telegraphed blow, 4 m knockback, a lit weak spot taking x2.2) | Stay outside 6 m; read the telegraph from the zombie's attack mode and step out sideways on reaction time (0.25 to 0.55 s against a 1.2 s window); aim at the weak spot only when its bulb is in the view cone; add the escorts to the target utility with a lower weight than the boss's blows on a teammate; the boss's knockback is a reason to keep back from walls. |
| **Midnight Stampede** (runners only, 110% count, spawning 1.8 times as often) | Do not run: runners are 1.4 times faster. Hold a choke or wall with the shotgun or SMG, back covered, boards up; kill by sustained damage. |
| **Crawl Space** (crawlers only) | Aim low from the look data; boards do not help (they go under); prefer grenades and the shotgun; keep moving, they are slow (x0.5). |
| **Low ammunition** | Tactical reload; swap to the best weapon with ammunition; buy rounds in the next break; melee when everything is dry (the crowbar never runs out, 82 damage a second) but not into a pack of three or more. |
| **Trapped** (no path with 1 m of clearance for 2 s) | Fight with the best sustained weapon; use a grenade at 4 m or more from itself; jump onto a car roof or other curated link; call for cover; no teleport. |
| **Last one alive** | See *Revives*. |
| **Generator dry** | The view range collapses (8 m); the bot closes in on humans, shoots only seen targets, and a maintainer buys fuel. |
| **A human goes idle or leaves** | The bot does not wait for them in a fight; it keeps following the largest group and, in a break, goes on errands. A human who leaves frees the slot for a bot (decision 7: a human who joins inherits it). |
| **Door rebake in progress** | Paths are dropped; the bot holds position and shoots until the mesh answers. |
| **Telegraph and special round announcements** | `special_round_announced` is shown to people, so the bot may read it: it buys ammunition and repairs in the longer break, and sets its stance (choke for the stampede). |

## Determinism and testability

- **Fixed tick.** The bot thinks on `server.tick_count % period == slot_offset`; the motor runs every tick; no
  `Time`, no engine delta other than the step it is given, no `randf`: one `RandomNumberGenerator` per bot seeded from
  the match seed and slot id. Iterations that influence a choice go in sorted id order. This is the rule the rules engine
  and the zombie sim already follow ([rules engine](rules-engine.md), [zombies](zombies.md#what-was-decided)).
- **Same commands as a human.** The bot is nothing but its command stream. Test: record a bot night's `NightCommand`
  dictionaries, replay them through `Night.Mode.MANUAL` into a fresh server with the same seed, compare a state hash
  every 100 ticks. If they differ, the bot reached something the command did not carry.
- **Golden hash.** Four bots, 600 ticks, fixed seed: the hash of the command stream is a constant in the test; a change
  to it is a reviewed change.
- **Firewall.** The source scan above, plus: the bot class takes a `ClientState`, a profile, a seed, an `apply`
  callable, a sight callable, a lit callable and the static level data, and has no other constructor argument.
- **Balance simulator.** The model simulator stays the fast tuning tool (a night in 0.05 to 0.15 s). Bots run in the
  real server, headless: about 0.3 to 0.5 ms a tick (measured), so a 20-minute night is 36,000 ticks at 30 Hz, about
  15 to 40 s of CPU; a 100-night cell on four parallel suites is a nightly job of 10 to 20 minutes, not a pull request
  gate. Each profile reports its measured hit rate, dodge and uptime so the model's `SimSkill` can be fitted to the bot
  and, later, to people's telemetry.

## Server cost

*Measured* on `main` (headless Godot 4.7.2, a Windows machine shared with other agents, so the second digit is noise):

| What | Measured |
| --- | --- |
| Whole `Night.tick` (link, server step, the real autopilot) in rounds 1 to 5, 0 to 9 zombies alive | 0.27 to 0.47 ms average (37,605 ticks, the bot alive in round 6) |
| `Autopilot.decide` alone, 0 / 10 / 30 / 40 zombies spread over 50 m, with the real ray tests and a path query | 85 / 58 / 107 / 166 microseconds (600 calls each) |
| One `map_get_path` across the lot | 234 microseconds |
| `ZombieSim` step, 40 zombies ([zombies research](zombies.md#types-in-the-night)) | 0.65 to 0.75 ms |

The Autopilot decides at 60 Hz and queries a path every tick. The plan thinks at 5 to 10 Hz (the 30 Hz server tick is
33 ms), paths at 3 Hz, and runs only the cheap motor each tick:

| | Per bot, per 30 Hz tick (estimate) |
| --- | ---: |
| Brain, one think in three at 0.2 ms | 0.07 ms |
| Paths, 3 a second at 0.23 ms | 0.02 ms |
| Motor, every tick | 0.02 ms |
| **Mean** | **about 0.1 ms** |
| Worst tick (a think plus a path, 40 zombies) | under 0.5 ms |

Three bots then cost about 0.3 ms mean against a 33 ms tick: 1%. **Budget**: bots together under 5% of the tick, so
0.5 ms worst per bot (a test fails above it with 40 zombies in the frame, the rules' cap at four players from round
21 on, and the most the lot ever stands: [crowd budget](../design/zombies.md#crowd-budget)), and
think ticks staggered by slot so they never land together. Perception is bounded by design: a cheap angle and distance
test first, then at most six rays a think (the closest candidates in the cone). The 40-zombie ceiling of the director
and the `alive_cap` (28 solo plus 6 for each extra player) bound N.

## How to test bots so they are not buggy

**Layers.** Each is cheaper and more precise than the next; a bug is caught in the lowest one that can show it, as
Game AI Pro's chapter on AI testing puts it: "most complicated failures are a result of simple underlying causes that
can be tested in isolation" ([Skarupke](http://www.gameaipro.com/GameAIProOnlineEdition2021/GameAIProOnlineEdition2021_Chapter01_Automated_AI_Testing_Simple_tests_will_save_you_time.pdf)),
and its stress categories (perception, reaction, targeting, unreachability, navigation, weapon handling, group and
timing) are ours too ([Ocio Barriales](http://www.gameaipro.com/GameAIPro3/GameAIPro3_Chapter07_How_to_Build_Robust_AI_for_Your_Game.pdf)).

**1. Pure unit tests** (milliseconds): the perception filter, the aim model's distributions, the economy chooser as a
   table (points, prices, inventory in; the purchase out), the revive risk function, the stuck detector fed synthetic
   position traces, follow-position scoring.
**2. Scenario tests** (GdUnit4, headless, a `NightFixture` with scripted zombies; 1 to 5 s each). Named, so a failure
   says what broke. First list:

| # | Scenario | Asserts |
| --- | --- | --- |
| 1 | One walker in the avenue | Shot dead; first shot not before the reaction floor |
| 2 | Walker behind a wall, bot facing away | Never believed; never aimed at |
| 3 | A zombie steps from behind a car | Believed after the delay, not before |
| 4 | Downed human, clear | Revived; the claim table has one claimer |
| 5 | Downed human, three zombies at the body | Clears first, then revives; no revive started inside the danger time |
| 6 | Revive under a hit | Aborts under the rule, retries after clearing |
| 7 | Two bots, one downed human | One revives, the other covers |
| 8 | Door price met, a human at the door | Defers; buys after the grace |
| 9 | Refused buy (`AMMO_FULL`) | Backs off 30 s; no buy loop |
| 10 | Dry magazine, no reserve | Swaps to melee; buys rounds in the break |
| 11 | Breach with a board down in a break | Repairs; stops when a zombie is at the boards |
| 12 | Boss telegraph | Steps out within reaction time plus a tick; no hit taken in 20 trials |
| 13 | Runners only | Holds a choke; does not sprint away |
| 14 | Crawlers only | Aims low; hit rate within the profile band |
| 15 | Trapped in a corner | Fights, jumps on a link if one exists, reports, never teleports |
| 16 | Last alive, human down, zombies near | Survives to the round end or revives safely |
| 17 | Human walks at the bot in a gap | The bot yields within 1 s |
| 18 | Door bought, mesh rebaked | Follows the human through; no path error printed |
| 19 | Goal unreachable | Marks it, takes another errand, no query storm |
| 20 | Each known obstacle (car gaps, the booth ramp, the generator cage) | Stuck ladder solves it inside 6 s |
| 21 | Fuel under 25% | One bot buys; others do not |
| 22 | A human pings a door | Buys when affordable |
| 23 | Late join | The bot's slot is released cleanly |
| 24 | Replay of a bot night | Same hash as the live run |
| 25 | Golden command hash | Constant |
| 26 | Decision time with 40 zombies | p99 under 0.5 ms |
| 27 | A script error inside the brain | Watchdog disables the brain, the motor holds and follows, a telemetry event fires |
| 28 | Coverage matrix | Every shop item, weapon and prompt kind has a bot rule or a written waiver |

**3. Soak** (a script like `autopilot_night.tscn`): whole nights with four bots and no human, over seeds and profiles,
   headless, with a wall-time limit per night. Pull-request gate: 3 nights of at most 5 rounds, under 3 minutes.
   Nightly: 100 nights per cell. Gates: no engine `ERROR`; no stuck episode over 10 s; stuck seconds under 1% of
   walking time; no idle bot (no command change) over 5 s with a zombie in view; no bot farther than 25 m from the
   nearest human for over 20 s outside an errand; no rejected-buy loop; the decision p99 holds.
**4. Metrics and telemetry.** Per bot per night, written as a line of JSON (and as counters in the platform's
   telemetry when it exists):

| Metric | Why |
| --- | --- |
| `stuck_seconds`, `longest_stuck`, `ladder_depth_max` | Navigation health |
| `idle_with_threat_seconds` | Passivity |
| `blocking_seconds` (inside a gap or a human's cone) | Getting in the way |
| `shots`, `hits`, `head_share`, `kill_share`, `damage_taken` | Fairness and parity |
| `revive_attempts`, `successes`, `aborts`, `deaths_reviving` | Revive judgement |
| `buys`, `rejected_buys`, `points_idle_max` | Economy |
| `distance_to_human_p50`, `p95` | Staying near |
| `think_us_p50`, `p99`, `path_queries`, `path_us` | Cost |
| `rounds_reached` | Survival |

   A ring buffer of the bot's last 300 decisions with the beliefs that produced them is dumped on a stuck event, a bot
   death and a failed test, the "why" that Game AI Pro's chapters on logging visualisation and in-game scrubbing
   describe ([FFXV logging](http://www.gameaipro.com/GameAIPro3/GameAIPro3_Chapter03_Logging_Visualization_in_FINAL_FANTASY_XV.pdf)).
   An in-game debug overlay draws the path, the target, the cone and the chosen node.
**5. Bot against human, in the balance simulator.** For each profile and team size, run the real bots 100 nights and
   compare the distribution of the round reached with the simulator's matching `SimSkill` cell (weak 5, average 12,
   strong 15 rounds as medians solo today): the median within 1.5 rounds, and the survival curves close (Kolmogorov
   distance under 0.2). Compare the hit rate, head share and revive times to the model's assumptions. Then compare a
   night with bots filling empty slots with the same night of humans once telemetry has humans. A bot-filled night
   must not be *easier* than a human one, or the bots are superhuman, or *harder*, or they are a burden (the rules
   scale the boss and the alive cap by player count, so a filled slot makes the night harder for the humans unless
   the bot pulls its weight).
**6. Chaos and fuzz.** Random zombie placement, a human teleported to a random mesh point, doors bought at random
   moments, random event drops: the soak gates must hold.

## Failure modes and how each is avoided

| Failure | Where it was seen | Avoided by |
| --- | --- | --- |
| Heals or shops while a teammate is down | L4D (improved-bots list) | Errands and consumables are below Rescue and Fight in the tree; no shopping with a teammate downed or any zombie within 12 m |
| Revives into a pack, or never revives | Toxic Commando, L4D, Vermintide | Risk check, clear first, commit and abort hysteresis, telemetry on outcomes |
| Gives up a revive on the first hit | L4D | Abort rule needs a loss of 20 health in a second or under 30% health |
| Suicidal chase of specials | Vermintide | A leash of 12 m from the nearest human unless the target is on a downed teammate |
| Charges into hordes with melee | Vermintide | Melee only when dry or the target is alone; never into three or more |
| Stuck, left and right dance | L4D, Vermintide, B4B | Stuck ladder, unreachable-goal memory, soak gate, scenario 20 |
| Panics off a ledge | Vermintide 4.2 | Reflex moves projected onto the mesh; no off-mesh moves except curated links |
| Follows only the leader in front, abandons a downed human | B4B | Group centroid weighted to need; revive and cover rules |
| Clumps, body-blocks gaps | B4B, Vermintide | 2.5 m bot separation, no stopping in gaps, firing-cone rule, yield |
| Takes the team's resources | Vermintide 4.2, L4D medkits | Door etiquette, kill courtesy, repair purse rule, reserve |
| Reaction shots, perfect aim | The problem Vermintide cites | Reaction floor 0.20 s, spring turn, noise, tests of the distributions |
| Wallhack | Any bot with the full frame | Perception filter, event allow-list, firewall test, memory that is never shot at |
| Teleports | Vermintide (stuck) | No teleport; report instead (decided: no teleporting bots) |
| Spams pings | B4B | Per-line and global callout cooldowns |
| Cannot be told anything | B4B players, Vermintide tomes | A small set of single-meaning pings |
| Does not do a job a human does | Killing Floor mutator, Toxic Commando | Coverage matrix test: every shop item, weapon and prompt kind needs a bot rule or a waiver |
| Rots after release | The abandoned L4D bots mod; Vermintide's open reports | Soak in CI, the coverage test, and an owner in each phase |
| Makes the night easier or harder than people | Ellie's "killing machine" | The parity batch against the simulator, damage left alone |
| Predictable and exploitable | Practice bots | Seeded variety in positions and timing |
| Fires or throws into teammates | Any shooter | No grenade within 4 m of a teammate; blasts spare the party for now, checked again if friendly fire arrives |

## Phases

Order is dependency order. Each phase ends with its tests green, the nightly soak not worse than the last, and the docs
page updated. Phase issues are #224 to #231.

### Phase 0: the game surface a bot needs

Issue: #224.

Not bot work; without it a bot is missing hands. Revive (an action, a command edge, a channel time, bleed-out, the
rules' events), circuit switches (#206), the fuel purchase spot, pings (a message and a rule), `dir` checked against
yaw and pitch on the server (#55, #163), crouch (#73) and low ledge step-up (#78) if the maintainer wants them in v1.
**Done when** a person can do each in a night, the rules and server tests cover them, `RulesAction` and `NightCommand`
carry them, and the balance simulator models revive with the real numbers. **Tests**: rules tests for each new action
(accept, reject, snapshot round trip), a night test of a revive through `NightCommand`, a test that a shot whose `dir`
disagrees with the view is refused or clamped.

**Built (#224).** By the time it was built, circuit switches (#206), the fuel spot, crouch (#73) and low ledge step-up
(#78) were in the game, so the phase added what was left:

- **Revive.** `RulesAction.revive(player_id, target_id)`: refused outside a round, for an unknown or downed reviver,
  for oneself and for a target who is up. It gets the target up with `HealthTuning.revive_fraction` (0.5) of their
  health and restarts the wait before mending; `player_revived` now names the `reviver_id` (0 at a round's end, which
  still gets everyone up with all their health). The channel is the server's: holding `use` within
  `NightTuning.revive_reach` (2.2 m) of a downed teammate for `HealthTuning.revive_seconds` (6.0), with the reviver
  free to let go, step away or be struck down, which starts the time over. The frame carries `reviving` and `revive`
  (0 to 1) per player, the prompt `{kind: revive, id, progress}` comes before a door's, and `revive_started` and
  `revive_stopped` (reason `released`, `moved`, `down`, `done`) go to the clients. **No bleed-out** (the design says a
  downed player waits to be raised or for the round's end), and **no points for a revive** (the rescue pay of the
  progression design is XP, from `player_revived.reviver_id`). The snapshot gained no field, so its version stays 8.
- **Pings.** `NightServer.PING` / `ping` {kind, pos, subject} and a ten-byte client message (`NetWire.Type.MARK`, rate
  limited at 2 a second): `here`, `door` (by index), `ammo`, `enemy` (a live zombie's id) and `downed` (a downed
  teammate). The server checks every claim (reach 70 m, a shut door, an ammunition spot within 4 m, a live zombie, a
  downed player), snaps the position to the thing named, keeps one mark per player for 20 s and one new mark a second,
  and puts them in the frame (`pings`) and the feed (`ping_placed`, `ping_cleared`). A person presses `Z`, the middle
  mouse button or the pad's right D-pad; `PingAim` picks what the crosshair is on. Markers show over the view
  (`NightMarkers`). The `NetWire` version does not change: a new type is additive.
- **Shots follow the view.** `NightServer.aims_with_view`: a shot whose `dir` is more than 10 degrees from the view's
  forward (`view_dir(yaw, pitch)`) is refused with `fire_rejected` / `aim_mismatch`. `NightCommand.aim_along` sets
  both; the Autopilot now turns its view to the target and walks its own way. A person's camera measured at under one
  degree from its own yaw and pitch over 15 poses.
- **The balance simulator** raises a teammate with the rules' own `revive` action and reads the six seconds and the
  half health from `HealthTuning`, so the two cannot drift.

### Phase 1: the bot host, perception, aim and the test harness

Issue: #225.

`BotClient`, `BotProfile`, `BotPerception`, `BotMotor` (aim and trigger only), the event allow-list, seeded random
streams, telemetry and the decision ring buffer, the multi-player `NightFixture`, the replay and golden-hash tests, the
source scan. The Autopilot becomes the first profile on this host (its behaviour unchanged) so nothing regresses.
**Done when**: four hosted bots survive three rounds in a soak without an `ERROR`; scenarios 1 to 3 and 24 to 28 pass;
the reaction and turn-rate distributions are inside their bounds; the firewall and replay tests pass; the decision p99
is under 0.5 ms at 40 zombies; the page's cost section is updated with the measured numbers.

### Phase 2: movement

Issue: #226.

Path following with a cache and a budget, door-rebake handling, unreachable memory, steering among 12 headings with mesh
projection, follow positions, yielding and gap rules, the stuck ladder with `bot_stuck`, curated `BotLink` markers.
**Done when**: scenarios 17 to 20 pass; a 20-minute soak of four bots shows stuck seconds under 1% of walking time and
no episode over 10 s on any seed; bots stay within 12 m of the nearest human for 95% of a round (outside errands);
no path error is printed across a soak with door purchases. **Tests**: the stuck detector on synthetic traces, the
follow scorer, a nav test on every area of the opening-order test, a negative control (a blocked gap) that the ladder
must solve or report.

### Phase 3: combat and ammunition

Issue: #227.

Target utility, weapon ranking and swaps, tactical reloads, melee fallback, grenades with the safety rule, boss
telegraph dodging and weak-spot aim, the special-round stances, leash and kill courtesy. **Done when**: scenarios 10, 12
to 14 pass; per-profile hit rate and head share fall in the `SimSkill` bands (Rookie to weak, Regular to average,
Veteran to strong); a four-bot night passes the first boss night in at least the share of nights the simulator
predicts for its skill (within 15 percentage points).

### Phase 4: economy, repairs and the generator

Issue: #228.

The shopping chooser, reserve, door etiquette, repair purse rule, fuel and circuit manager, backing off after refusals,
callout lines for buying. **Done when**: scenarios 8, 9, 11, 21 and 22 pass; in a soak no bot holds over twice the next
purchase for a round, no rejected-buy loop occurs, every door is bought in plan order without a human present, and the
points spent by category match the simulator's shopping model within 20%; the coverage matrix (28) is green.

### Phase 5: team play, revives and edge cases

Issue: #229.

Roles as stances, the claim table, the risk check, clear-then-revive, commit and abort, last-standing logic, trapped
logic, callouts and human pings. **Done when**: scenarios 4 to 7, 15, 16 and 23 pass; in a soak of four bots against
the real zombie mix, revive success is at least 70% of attempts and `deaths_reviving` under 10% of attempts; no more
than one bot at a time on an errand; the callout rate is under one line per bot per 10 s and none names an unseen
zombie.

### Phase 6: filling slots, difficulty and the server

Issue: #230.

The server fills empty slots with bots on a room setting (off, fill to two, fill to four), labels them in the lobby and
the HUD, handles a human joining or leaving a bot's slot, gives the profiles names and looks, and exposes a kill-switch
and a per-room bot cap, to the [decisions](#decisions-of-the-maintainer). **Done when**: a networked match over
the real transport with two humans and two bots runs 10 minutes in CI without a divergence or an `ERROR` (with #56);
the server's measured bot cost is inside the budget; a human takes over a slot mid-round without losing the round.

### Phase 7: validation at scale and tuning

Issue: #231.

The nightly soak (100 nights a cell), the parity batch against the simulator for every profile and team size, a human
playtest with telemetry, fitting `SimSkill` to the measured bots, and the retune of the rules' player scaling if bots
make filled nights different from human ones. **Done when**: the parity gates in the testing section hold for three
consecutive nightly runs; a written report lists each profile's measured numbers; the page is updated; known
limitations are issues.

## Decisions of the maintainer

The seven open questions of the first draft were answered on 2026-11-02: **all seven recommendations accepted**.
They are decisions now, not options; the phases build to them.

| # | Question | Decision | What it means in the build |
| --- | --- | --- | --- |
| 1 | Teleport as a last resort? | **No teleporting bots.** | The stuck ladder ends in a report (`bot_stuck`) and a walk back along the breadcrumb trail, never a jump to the humans. A bot that cannot reach anyone fights where it stands. |
| 2 | Label bots? | **Yes, bots are labelled as bots.** | A mark in the lobby, the roster, the HUD's player box and the feed (`BOT` after the name); never in the command, which stays identical to a person's. The name comes from the profile (Phase 6). |
| 3 | Do bots earn account progression? | **Bots earn points in the night, not XP.** | In-night points work as for a person (a bot buys doors with what it kills for). Account XP, rescue pay and mastery are never paid to a bot, and a night with bots is marked in the stats. The progression code reads `player_revived.reviver_id` and `player_added.bot` to skip bots; a bot that revives a human farms nothing. |
| 4 | Player scaling | **Bots count for zombie scaling.** | The boss health, the alive cap and the spawn rate scale with the number of seated players, bots included (a bot is a player to the rules: `add_player`). Phase 7 may weight a bot below one; the default is one. |
| 5 | Can people give bots orders? | **Orders by pings only.** | The five pings of Phase 0 (`PingBoard.KINDS`: here, door, ammo, enemy, downed) are the whole vocabulary; there is no command menu and no text. |
| 6 | Voice | **No bot voice for now.** | Callouts are `bot_say` lines in the feed only; no audio assets are made for them until the maintainer asks. |
| 7 | A human takes a bot's slot | **A joining human inherits the bot's slot.** | The human gets the bot's seat, body, points, weapons, ammunition, grenades and health as they stand, and the bot is removed in the same tick. No reason to leave and rejoin. A human who leaves leaves the slot to a bot again (Phase 6). |

## Sources

"Read", "fetched" and "reported" are defined at the top of [What shipped games did](#what-shipped-games-did).
The Booth slides, the Game AI Pro chapters named in the text and the Ellie chapter were read from extracted PDF text;
the rest were fetched or reported.

| Subject | Sources |
| --- | --- |
| Left 4 Dead | Mike Booth, [Replayable Cooperative Game Design: Left 4 Dead](https://cdn.fastly.steamstatic.com/apps/valve/2009/GDC2009_ReplayableCooperativeGameDesign_Left4Dead.pdf), GDC 2009. |
| Left 4 Dead bots | [Improved Survivor Bots](https://github.com/justin-chellah/improved-survivor-bots) (the fix list of a community mod). |
| Counter-Strike bots, NextBot | Counter-Strike [BotProfile.db](https://gist.github.com/so0k/7505931) (community copy); [GDC Vault listing of the 2004 bot talk](https://www.gamedeveloper.com/design/gdc-vault-adds-valve-biofeedback-i-counter-strike-i-i-half-life-2-i-talks) (reported); [Valve wiki: NextBot](https://developer.valvesoftware.com/wiki/NextBot) (reported). |
| Vermintide 2 | Fatshark, [How Bots Work in Vermintide 2](https://www.vermintide.com/news/2018/12/17/dev-blog-how-bots-work-in-vermintide-2) and [Bots in 4.2](https://www.vermintide.com/news/dev-blog-bots-in-42); [patch 4.2 summary](https://www.player.one/warhammer-patch-42-bot-improvements-general-fixes-and-more-139082), [forum](https://forums.fatsharkgames.com/t/about-bots-again/45239/98), [bug thread](https://forums.fatsharkgames.com/t/bugs-with-bots-pathing-getting-stuck-falling-off-ledges/31245) (reported). |
| Back 4 Blood | Back 4 Blood: [Game Revolution](https://www.gamerevolution.com/?p=695027), [Pure Xbox](https://www.purexbox.com/news/2021/08/back_4_blood_dev_confirms_bots_and_difficulty_balance_will_be_improved_for_launch) (reported). |
| Toxic Commando, Killing Floor, CoD | [Toxic Commando bot feedback](https://community.focus-entmt.com/focus-entertainment/toxic-commando/ideas/15797-%F0%9F%A4%96-suggestions-to-improve-bots-greatly-benefits-solo-players); [Killing Floor 2 mutator comments](https://steamcommunity.com/sharedfiles/filedetails/comments/1350604221) (reported); [Bot Warfare T6](https://github.com/ineedbots/t6_bot_warfare). |
| Other companions and practice bots | [Deep Rock Galactic wiki: Bosco](https://deeprockgalactic.wiki.gg/wiki/Bosco), [Warframe forum](https://forums.warframe.com/topic/1255114-companion-ai-is-broken/), [Dot Esports on Valorant's practice bots](https://dotesports.com/valorant/news/riot-silently-updated-valorants-practice-bots-but-now-theyre-out-of-control) (all reported). |
| Game AI Pro | Game AI Pro: [ch. 4 behaviour selection](http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter04_Behavior_Selection_Algorithms.pdf), [ch. 9 utility theory](http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter09_An_Introduction_to_Utility_Theory.pdf), [ch. 10 utility in a tree](http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter10_Building_Utility_Decisions_into_Your_Existing_Behavior_Tree.pdf), [ch. 12 HTN](http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter12_Exploring_HTN_Planners_through_Example.pdf), [vol. 2 ch. 35 Ellie](http://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter35_Ellie_Buddy_AI_in_The_Last_of_Us.pdf), [vol. 3 ch. 7 robust AI](http://www.gameaipro.com/GameAIPro3/GameAIPro3_Chapter07_How_to_Build_Robust_AI_for_Your_Game.pdf), [vol. 3 ch. 9 behaviour tree pitfalls](http://www.gameaipro.com/GameAIPro3/GameAIPro3_Chapter09_Overcoming_Pitfalls_in_Behavior_Tree_Design.pdf), [online 2021 ch. 1 automated AI testing](http://www.gameaipro.com/GameAIProOnlineEdition2021/GameAIProOnlineEdition2021_Chapter01_Automated_AI_Testing_Simple_tests_will_save_you_time.pdf). Also read, not quoted: [Crytek's target tracks](http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter31_Crytek's_Target_Tracks_Perception_System.pdf), [vision zones](http://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter04_Vision_Zones_and_Object_Identification_Certainty.pdf). |
| Architecture talks | Isla, [Handling Complexity in the Halo 2 AI](https://www.gamedeveloper.com/programming/gdc-2005-proceeding-handling-complexity-in-the-i-halo-2-i-ai), GDC 2005; Orkin, [Three States and a Plan](https://pages.cs.wisc.edu/~dyer/cs540/handouts/gdc2006_orkin_jeff_fear.pdf) (reported); Mark and Dill, [GDC 2010](https://gdcvault.com/play/1012410/Improving-AI-Decision-Modeling-Through) (reported). |
| Engines and docs | [LimboAI](https://github.com/limbonaut/limboai); Godot, [Using NavigationAgents](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationagents.html); Unreal, [AISenseConfig_Sight](https://dev.epicgames.com/documentation/en-us/unreal-engine/python-api/class/AISenseConfig_Sight); Unity, [GameCrawler](https://docs.unity3d.com/Packages/com.unity.automated-testing@0.7/manual/GameCrawler.html) (reported). |
| Reaction time and aim | Reaction time: [PMC6916673](https://pmc.ncbi.nlm.nih.gov/articles/PMC6916673); Glavin and Madden on bot handicaps, [arXiv 1806.05554](https://arxiv.org/abs/1806.05554) (reported). |

Not found despite searching: any design write-up of Back 4 Blood's bots, of Overwatch's or Valorant's practice bots, of
Deep Rock Galactic's Bosco, of Killing Floor 2's own (absent) bots, and any Valheim companion source. GDC Vault talks
other than the free ones are behind a login and were not read.
