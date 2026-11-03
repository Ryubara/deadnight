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
- **Orders**: a bot roams by default and does its own thing; it comes to a person only for a revive or a ping. A
  person gives the team's bots one of three orders, **Follow**, **Roam** or **Hold**, with the command wheel; the order
  travels as a player command and every bot reads it from the frame ([Orders](#orders-follow-roam-and-hold-641)).
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
| Zombie navigation | `zombies/navmesh_baker.gd` | One mesh (cell 0.25, agent radius 0.5, height 1.75, climb 0.25, slope 45 degrees, contour error 1.0 cell); rebaked when a door opens. The bot uses `NavigationServer3D.map_get_path` on it. |
| Balance simulator | `tools/balance/` | `SimSkill` levels (weak, average, strong) with accuracy 0.45 / 0.65 / 0.82, head rate 0.68 / 0.81 / 0.85 (0.06 / 0.15 / 0.30 before the hit zones followed the bodies, #745), dodge, read; the reference for "like a human". |

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
**6. Stand by the order** (`BotOrders`, [Orders](#orders-follow-roam-and-hold-641)): **Follow** takes a rated follow
position near the person who gave the order; **Hold** stands at the spot the order was given; **Roam** (the default)
walks to places across the lot and looks about from each.
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
| **Events** | An allow-list: what the feed and HUD already show (purchases, rounds, downs, own damage, boards torn or repaired, special round announced) and, about itself, the burst of its own flare (`lure_started`, #646). `zombie_spawn_requested` and anything with server-side detail are dropped before the brain. The allow-list is a constant and a test asserts the dropped types. |
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
| Track error at 15 m (degrees, 1 sigma) | 14 | 4 | 2 |
| Fire slop (times the hit cone the trigger waits for) | 6 | 3 | 1.8 |
| Head-aim rate | 0 (0.07 until #568) | 0.30 | 0.75 |
| Weak-spot rate (the boss's lens, when it faces the bot) | 0.25 | 0.50 | 0.80 |
| Telegraph read (a boss's blow made out, then stepped out of) | 0 | 1.0 | 1.0 |
| View cone (degrees) | 80 | 110 | 110 |
| Fire jitter (s) | 0.15 | 0.08 | 0.04 |
| Think rate (Hz) | 5 | 8 | 10 |
| Retreat early (metres of margin) | 0 | 1.25 | 1.5 |
| Revive eagerness (risk it accepts) | low | medium | medium |

Calibration target: a profile's measured hit rate, head share and dodge land inside the corresponding
`SimSkill` (weak 0.45 / 0.68 / 0.17, average 0.65 / 0.81 / 0.55, strong 0.82 / 0.85 / 0.80) so the simulator and the
bots tell the same story; the profile numbers move to meet it, the simulator's do not (**except** when the world under
them changes: the hit zones that follow the bodies, #694, moved the head share from 6 / 15 / 30% to about 68 / 81 / 85%
and the dodge, so `SimSkill` was set to the bots' new readings and the game retuned around it, #745: see
[the balance simulator](balance-simulator.md#the-headshot-retune-745)). **The table above is the
phase 3 result** (the proposal was 3.0 / 1.8 / 1.0 degrees of track error, 0.05 / 0.12 / 0.20 head-aim and a retreat
margin of 5 / 7 / 9 m): a bot that fires only when its view is on target hits nearly everything it fires at, so the
misses had to come from a trigger that fires when the view is roughly there (`fire_slop`) and from a wide wander of the
view, and the early retreat of the proposal gave a dodge of 0.7 to 0.8 for every profile, stronger than the strong
level. [Phase 3](#phase-3-combat-and-ammunition) has the measurements.

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
| **Staying near the person (the Follow order)** | After Ellie: a *follow region* around the group (centroid of the humans, weighted toward the one who needs help), candidate positions by nav rays, rated each think by distance (3 to 7 m in a fight, 4 to 10 m outside), the same side as the leader, not in front, at least 2.5 m from other bots, in light, not at a breach, and outside the leader's firing cone. Allowed to arrive "close enough"; no pass through the leader. Vermintide assigns follow points so each bot takes the cheapest one. |
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

### Goals the body cannot reach (#677)

The walking mesh runs through each breach's gap into the pocket the dead break in from, and the breach's boards sit on a
physics layer of their own (players only) that the bots' sight ray does not look at. A goal in the pocket, or past the
fence within the 3 m snap, was therefore "on the mesh" with a good path, and the bot stood against the boards climbing
the ladder: 5 to 11 s episodes in a probe (the issue's 21 s was a roaming bot that kept coming back). Now a new path is
checked as a body walks it (`BotPath.walkable`: a ray along each segment at 0.15 m, `BotLevel.walk`, which sees walls and
boards and looks past people and zombies, `WorldProbe.static_distance`). Stopped with more than 1 m of path left, the
goal is marked unreachable at once (`walled_marks`) and the brain takes another; stopped with less, the path is cut
0.45 m before the thing, so a goal at the fence's own edge is walked to as near as the body gets. The roam's reach
question (`probe`) goes through the same check. `tests/night/test_bot_fence.gd` sends one bot to five pockets and to the
fence's edge (longest stuck under 3 s; 5 to 11 s on `main`); the old negative control for a wall the mesh does not know
turns the check off, since the check now sees such a wall.

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

The revive is the game's own (#224: the held `use` beside the body for `revive_seconds`, within `revive_reach`); the
bot only decides when to go, what to clear first and when to let go. These are the rules; phase 5 built them
(`BotRevive`, `BotReviveRisk`, `BotClaims`).

**Priority.** A downed human before a downed bot; among equals the one with the least time left; the nearest bot
claims (a shared claim table with a 3 s lease, ties by slot id), the others become *cover*.

**Risk check** (before committing, and again every think while reviving). Let `T` be the revive time (3.5 s,
`HealthTuning.revive_seconds`). For each known zombie estimate the time to reach the victim, path distance over
speed. The revive is safe when no zombie can reach victim or reviver within `T` plus a margin, or when the bot can
kill the ones that can in the time it takes them (their health from the round's public formula over the held weapon's
sustained damage, the numbers the simulator uses). Unsafe: go to *clear*.

**Clear.** Fight from a place with a line to the victim's surroundings, with a target bonus for zombies nearest the
victim; throw a grenade only when the victim is at least 4 m from the blast (the blast is 3 m, and a grenade hurts a
downed player 40%). This is what Toxic Commando's players ask for, and what Back 4 Blood's "always runs to the downed
player" bots skip. **The flare** (#646) is the other way to clear: the claimant that carries the flare gun fires it at
a spot far from the body, so the dead walk off to it ([the flare lure](flare-lure.md#bots-fire-it-646)); it hurts no
one, so the 4 m is about where the dead will stand (never within 4 m of a teammate), not a blast.

**Commit and abort.** Abort when more than one attacker is on the bot and it has lost 20 health in a second, or its
health is under 30%; but once progress passes 60% abort only under 30% health. A bot that aborts goes to clear
and retries. Hysteresis fixes both failures players report: "give up too easily" (L4D) and "die reviving" (B4B).

**Last standing.** Downed players get up at the round's end minus a tenth of their points, and the night ends when
everyone is down. So the last bot with humans down revives only if the risk check passes, else it kites to survive to
the end of the round, and it does not hold back from a revive that is safe.

**A downed bot** waits for a human: it does not crawl (no mechanic), and its callout fires once.

**Coming back for an unsafe body (#673).** A body judged `UNSAFE` (a pack, or one or two bosses whose kill time is 34 s
and 67 s) sends nobody to the hold, and until #673 a bot that was not the last one up went on as before, so when the
pack had gone the walk was longer than the clock had left (`LATE`). Now the nearest bot that is not the last one
*stages* (`BotRevive.Mode.STAGE`): 14 m from the body (a walk of about 5 s of the 45), shooting the zombies nearest the
body first, and the usual verdict, claim and hold take over the moment it is clear. A claimant on its way that has come
no nearer than 0.5 m in 5 s is stuck (seed 7 of the soak: a bot three metres from a body with a zero wish held the claim
for 30 s while the two others only covered): it gives the claim up and stays out of that body for 20 s. The revive soak
prints a `BLEED` line for every body that bleeds out: per bot the seconds by reason and mode over the whole fall
(`unsafe/STAGE`, `late/NONE`, `claim_lost/COVER`...), the closest it came, and its last account (why, verdict, how many
zombies and the kill seconds, distance, claim). Measure: [the numbers](#revive-return-soak-673).

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

## Orders: Follow, Roam and Hold (#641)

The maintainer, 2026-11-02, answering the within-12 m gate of #564: "Bots should be able to free roam and do their own
thing. The only time they really go to the player is when the player needs a revive or if the player ping somewhere with
middle click on mouse (needs a control for mobile/gamepad). Perhaps we can build a behavior system that listens to
commands from the player, like a command wheel for the bots to either stick with the player, or "fan out", or "hold".
Those three things "Follow", "Roam", "Hold" ...". So the bots no longer follow by default, and decision 5 (orders by
pings only) is superseded: pings stay, and three standing orders are added. The command wheel that gives them is #642.

| Order | What the bot does | Where it is in the tree |
| --- | --- | --- |
| **Roam** (the default) | Does its own thing: fights what it meets, shops, mends boards, looks after the generator, and walks from place to place across the lot (`BotRoam`), away from the person and from the other bots. | Rung 6. A fight, an errand, a revive and a ping come first, as for every order. |
| **Follow** | Sticks with the person who gave the order: `BotFollow`, with the band #564 tuned (4 to 10 m calm, 3 to 7 m in a fight). The person leaves, or is dead: the bot roams. | Rung 6. Roles (anchor, flank) are Follow's. |
| **Hold** | Stands at the spot the order was given, a place of a ring of 1.4 m about it by seat order, and fights from there; it does not back away, chase or shop, and leaves for a revive, a ping, a dodge or, with its reserve under a magazine, rounds ([needs](#needs-against-orders-692)), then comes back. | Rung 6. |

A downed person still pulls the nearest free bot through the claim table (`BotClaims`) and a ping pulls a bot, in
every order; the bot goes back to its order afterwards.

**The API.** `BotOrders` (`game/gameplay/bots/bot_orders.gd`): the orders `&"follow"`, `&"roam"`, `&"hold"` and
`issue(order, issuer_id, at: Vector3, bot_id := 0)`, which the wheel calls (`Night.bot_orders`, or `Night.give_bot_order`
with the issuer and the place filled in). One object serves both ends: with a `sender` (the link's `send`) it puts the
command on the wire; on the server it keeps the order and answers with a `bot_order_set` event. There is one order for
the team's bots; an order to one bot (`bot_id`) beats the team's for that bot until the next team order.

**The wire.** The order is a player command: `NetWire.Type.ORDER` (13), nine bytes (the order's index, the spot in
centimetres, the bot it is for), rate limited at 2 a second, and the protocol version is **13**. The server
(`NightServer.give_order`) takes the issuer from the connection, refuses a person who is down, an order it does not
know and a second order inside half a second, takes the spot from the message only when it is within ping reach of the
person (else it is where they stand) and puts it on the walking mesh. The order is a field of every frame
(`bot_orders`: `{team, bots}`), so a bot seated late, a bot a person takes over and a client that reconnects all read the
same order; `BotOrders.current(frame, bot_id)` is how a bot (and the wheel's HUD) reads it.

**Gates.**

| Order | Gate |
| --- | --- |
| Follow | Within 12 m of the person for 95% of the time a bot is up (outside errands), stuck under 1% of walking time, no episode over 10 s: #564's numbers, measured with `--order=follow`. |
| Roam | No idle bot: none stands with nothing to do (its note says roam or hold and it does not move) for more than 8 s (a look about at a place lasts 2 to 5 s). No stuck episode over 10 s and stuck under 1% of walking time. Buys and kills like the simulator: points spent over earned within 20% of the simulator's 0.80 to 0.87 (the mean of the bots), and the bots' kills no fewer than Follow's on the same seed. The bots spread: most of the time beyond 12 m of the person and 5 m or more from each other. |
| Hold | Within 3 m of the spot for 92% of the time a bot is under the stance (not on a trip for a revive, a ping, a dodge or an errand; the walk home is part of the trip), no episode stuck over 10 s, none idle over 5 s with a zombie in view. |
| Every order | A downed person and a ping each pull a bot, and it goes back to its order. |

**Measured** (the move soak, `game/tests/captures/bots_move_soak.tscn`, `--tough=3`, 20 game minutes, seeds 1 to 3, four
bots of the Regular, Veteran, Rookie and Regular profiles and the old autopilot as the person, who shops, buys doors and
fights; `--shop` gives the bots their errands. A shared machine, and two runs of a seed are not the same night, so read
the second digit as noise):

| | Roam | Follow | Hold |
| --- | ---: | ---: | ---: |
| Stuck share of walking time | 0.4, 0.9, 1.2% | 1.0, 2.1, 0.8% | 2.6, 6.5, 7.1% of a small walk (4 to 8 s per bot) |
| Longest stuck episode | 1.9, 5.1, 5.1 s | 4.5, 4.2, 1.5 s | 1.6, 2.0, 4.4 s |
| `bot_stuck` reports | 0 | 0 | 0 |
| Longest idle (the bot says roam or hold and stands) | 1.8, 2.9, 2.9 s | n/a (a bot well placed beside the person stands) | n/a |
| Mean distance to the person | 35 to 37 m | 13 to 15 m | 12 m (the person leaves the spot) |
| Mean distance between two bots | 38 to 39 m | 11 to 17 m | 2.6 to 2.9 m |
| Within 3 m of the spot | n/a | n/a | 0.94, 0.94, 0.89 of the time up; 0.97, 0.97, 0.93 on the spot |
| Kills by the bots (20 min) | 505, 489, 205 | 306, 166, 277 | 103, 140, 106 |
| Buys by the bots | 139, 137, 83 | 98, 110, 131 | none (a holding bot shops only for a pinged door, and for rounds when its reserve is under a magazine, from #692) |
| Think p99 | 5.7 to 6.0 ms | 1.6 to 2.3 ms | 0.5 to 0.9 ms |

Follow without errands (`--order=follow`, seeds 1 to 6, the #564 soak): within 12 m of the person **0.91 to 0.93 of the
time the bots are up**, stuck 1.0 to 2.0%, longest episode 1.3 to 4.3 s: the numbers of
[Tuning the follow soak](#tuning-the-follow-soak-564) hold, since Follow is the code that was there. With errands on,
the bots leave the person for them and the share falls to 0.62 to 0.69, which is why that gate is measured outside
errands.

What the numbers say. **Roam** walks 35 m from the person on average and kills and buys more than Follow does (a roaming
bot meets the dead on its own and passes more lockers); its stuck share is under 1.3%, and the longest episode is 5 s. The
think p99 is 5.7 to 6 ms on a machine that also ran three other soaks and a test run, about three times Follow's. The
cause is not separated: a roaming bot probes a few places for reach on a think (a path query each, at most four), and
it also does more errands than a bot beside the person (the shop soak's p99 was 5 to 6 ms before any of this); #564
owns the think budget. **Hold** keeps the spot against the real zombie mix, and a holding
bot is the one most often downed (6 to 12% of the bot-time in these seeds: it never backs away); the stuck share of a small
walk is bots giving way to the person or another bot. Shop soak (`bots_shop_soak.tscn`, four bots alone, so Roam):
points spent over points earned **0.82, 0.66, 0.76, 0.66** (mean 0.73) against the simulator's 0.80 to 0.87, up from
the 0.5 to 0.6 that bots following each other spent (#228): a roaming bot passes the lockers and the crane.

Found on the way: a stuck bot's repath moved its goal by a random metre or two, which at the fence put the goal outside
the walking mesh and had the bot stand against the posts for 14 s (the goal is now put back on the mesh); a roaming bot
asked about far places behind shut doors one query at a time and stood for 8 to 26 s (it now probes a few places in one
think, remembers the ones it cannot reach until a door changes the mesh, and wanders when none is left); a bot of the
parts' tests that stood still because no person was near started to roam when the default changed
([lesson](https://github.com/Ryubara/gdstudio/pull/257), tests now say what stance they stand for).

Not done here: the wheel and the HUD's word for the current order are #642 (on `main`, through `BotOrderLink`). The
roles of #229 (anchor, flank) are Follow's: a roaming or holding bot has none. The ping replies of #229 (hold here, shoot
that one, raise that one) and the claim table sit above every order.

## Play states: aggressive, careful, safe (#693)

The maintainer, 2026-11-03: "Bots need different playstates, aggressive if they're high on health, but more safe e.g.
keeping their distance when they're low health." The seed was #676's soak: a Hold bot is the one most often downed,
because it never backs away.

**The states.** `BotPlayState` (`game/gameplay/bots/bot_play_state.gd`, plain data, the only file with the logic; the
brain asks it and has no branch of its own). A bot's *share* is its health over its own full health (read from
`player_added`, `player_hurt` and `player_healed`, which carry `max_health` where the frame does not, so a health tonic
counts), less what danger costs: each zombie believed beyond the first within 4 m takes 0.08 off, at most 0.24.

| State | Enters below | Back up above | What the bot does |
| --- | --- | --- | --- |
| **Aggressive** | (the start) | 0.90 (from Careful) | As it always was: takes kills, may walk up to a zombie that is not coming (the crowbar's chase), keeps the profile's retreat margin (0 to 1.5 m). |
| **Careful** | 0.70 | 0.75 (from Safe) | Holds its range: retreat margin 2.5 m, no chase. Errands and the order go on. |
| **Safe** | 0.50 | | Keeps its distance: retreat margin 6 m, the retreat weighs room ahead 1.8 against 0.6 (open ground, not a dead end), and with no one to stay with it heads for the nearest teammate. No roaming and no errands. A revive is given up (or not begun) with a zombie within 8 m, unless it is the last one up. It stands and fights a zombie it cannot step back from, and a bot with a melee weapon backs away from a pack where a healthy one would swing. |

Each switch has two numbers (hysteresis), and a bot becomes bolder only after 2 s in its state (more careful at once),
so a bot on the edge does not flicker. All of it is on `BotProfile` under "Play states", editable in the inspector.

**How it ranks against the orders (#641).** The order is what the bot is for, the state is how it carries it out; a
revive claim, a ping and a dodge still sit above both, as for every order.

| Order | Safe | Careful |
| --- | --- | --- |
| **Follow** | Keeps the near side of the leader: a band of 2.5 to 4.5 m (against 3 to 7 m in a fight), so it stays inside the group; the leader's band is not left. | The usual band, a wider margin from the dead. |
| **Hold** | May step back from the held spot, at most 4 m (`hold_back`): the retreat is not bent toward the spot, and the bot does not walk back until it is better (the 3 m of the order's gate is given up while it is Safe). It returns when it is Careful again. | Holds the spot; backs off nothing. |
| **Roam** | Free: it stops wandering (no new roam goal, no errand) and fights where it stands, with the wide margin, until it is better. | Roams as usual, wider margin, no chase. |

**Needs against orders (#692).** The self-resupply of #692 is a table of need by order (`BotNeeds.RULES`). The play
state sits beside it, not in it (it is a state of the bot, not a need with a level and a place): a Safe bot's errands
are cut to a person's ping and its own need for rounds (`BotErrands.keeps_distance`, set by the brain from
`play.may_wander()`), and rounds count only with an **empty gun** (`Level.EMPTY`): a bot with nothing to shoot cannot
keep its distance by fighting, so it goes, whatever the order says; at `LOW` or `SHORT` it stays, silently. So under
every order a Safe bot with a gun that has rounds does not shop, and one with none goes to the nearest locker (by walk)
and comes back.

**Measured** (`bots_move_soak.tscn`, 20 game minutes, **the shipped health** (`--tough=1`: a tough night has no downs to
count), four bots (Regular, Veteran, Rookie, Regular) and the old autopilot as the person, the same seeds with the
states off (`--no-states`: the state is still read, nothing follows from it) and on. A night ends when everyone is
down, so a run is shorter than 20 minutes when it ends early; the rate is downs per bot per round reached. Seeds are
not reproducible to the digit (two runs of a seed are not the same night), so one seed's number says little: read the
total):

| Order | Seeds | Downs per bot per round, before | After | Downs per bot-minute, before | After | Kills per bot-minute, before | After |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| **Hold** | 8 | 0.340 (91 downs) | **0.209** (61) | 0.157 | 0.120 | 1.08 | 1.25 |
| **Follow** | 4 | 0.288 (38) | **0.150** (21) | 0.138 | 0.080 | 1.03 | 1.40 |
| **Roam** | 4 | 0.524 (65) | **0.140** (19) | 0.326 | 0.065 | 2.30 | 2.53 |

Two other sets were tried on Hold. The first (enter Careful below 0.60, Safe below 0.35, back up above 0.85 and 0.65)
gave 0.229 over the 8 seeds (54 downs). A wider margin and hold-back on the shipped thresholds (8 m, 3.5 m, 6 m) gave
0.283 over seeds 1 to 4, where the shipped set gave 0.186 and no states 0.333 on the same seeds: farther is not safer,
the bot leaves the spot's cover. The shipped set (0.70, 0.90, 0.50, 0.75) is the best of the three, though the gap to
the first set is inside the noise. The Hold gate of #641 (within 3 m of the spot for 92% of the time the bot is under
the stance) read 0.89 before and 0.92 after (the mean over the seeds of the share on the spot; a seed is 0.65 to 0.96,
the low ones are nights in which the person's walk and the first rounds take the bots away). Follow's gate (within 12
m of the person, 95% of the time up) was 0.92 before and 0.90 after: a Safe follower keeps to the near side, a Careful
one the usual band, and a bot that steps back from a zombie leaves the band for a moment. State changes were 0.5 to 2
a bot-minute on Hold and Follow (up to 4 on Roam, where a bot meets more of the dead): one change every 30 to 120 s a
bot (the test that pins the hysteresis: a wobble across a line changes the state once).

**What is left.** The `--downs` probe (seed 2, Hold, first thresholds) printed each bot's health over the four seconds
before it went down: of nine downs, five were a bot already Safe and stepping back (`hold_back`) at 10 to 30% health,
three were Aggressive (one went from full to half and then down inside two seconds), one was Careful. The states cut
the downs by a third to a half, they do not end them: a pack the bot cannot step away from still downs it, and the
regeneration (5 s without a blow, then 25 a second) does not start while a zombie keeps hitting.

**Proof.** `tests/bots/test_bot_play_state.gd` (23 cases): each switch and its hysteresis, a wobble across a line
changing the state once, the dwell, the pressure of a pack, the share of a bot with a tonic, every answer under each
order, the states-off bot answering as an aggressive one, a low bot backing away where a healthy one stands, a hurt bot's
wider margin, a holder stepping back within 4 m and no farther, and its retreat not bent toward the spot. The film:
`tests/captures/bots_play_states.tscn` (a Regular is hurt when a zombie comes near; the label names the state and the
health; `--trace` prints the metres to the nearest zombie). The trace of the run, from the second the zombie was 10 m
off: the bot was Safe at 25% and held 6.3 m from it (the zombie came on from 10 to 6.1 m, then stood off), regenerated
through Careful to Aggressive, and an aggressive bot stood while the zombie came from 5.8 m to 2.7 m.

**Not done here.** A Safe bot still stands against a zombie it cannot step back from (a wall behind it, a pack on every
side), and still shoots. The thresholds are one set for the three skills; a Veteran could be bolder and a Rookie more
careful (the profile fields allow it, nothing sets them apart yet). Safe does not yet go looking for a health tonic or a
medic spot (there is none in the lot).

## Needs against orders (#692)

The maintainer, 2026-11-03: "Bots should be smart enough to get their own ammo e.g. find the nearest ammo stash when
ammo is running low. Basically setting their task to grab ammo, but this needs a consideration on how it will conflict
when player requests to "follow" etc."

**What was there.** The economy (`BotEconomy`, #597) already bought rounds for a bot in a lull (the floor of
`BotProfile.ammo_floor_mags` magazines) and at once under one magazine, and a person's ammunition ping (#647/#670)
named the locker. What it lacked: no order was consulted (a bot that follows went anywhere, a bot that holds never
went), the nearest locker was the nearest by the straight line, and a bot held back by nothing had nothing to say.

**The table.** One place decides whether a need may take a bot from its order: `BotNeeds.RULES` (`bot_needs.gd`), a
table of need by order, each cell `{go, near, say}`. A need has a level (`BotNeeds.Level`), and the answer
(`BotNeeds.verdict`) is `GO`, `STAY` or `STAY_AND_SAY`. A person's ping is not in the table: it sits above every order
(`BotPings`), and `BotErrands` lets the marked rounds through under all three.

| Level of the need for rounds | Meaning |
| --- | --- |
| `LOW` | A gun worth rounds has less than `ammo_floor_mags` magazines in reserve. |
| `SHORT` | One has less than a magazine in reserve (the economy's "urgent"). |
| `EMPTY` | No round is left in any gun worth rounds, magazine and reserve alike. |

| Order | Goes when | Otherwise |
| --- | --- | --- |
| **Roam** | `LOW` or worse, anywhere: it does its own thing. | |
| **Follow** | The source is near the leader (within the follow leash, `BotCombat.LEASH` 12 m, of them, or within 3 m of the straight way to them) and the need is `LOW` or worse; or the gun is `EMPTY` (it goes anyway, then walks back to the leader). | Stays with the leader and says "I'M RUNNING LOW ON ROUNDS" (the callout of `BotSay.NEED_AMMO`, once, again after it was free of the hold); goes when the leader comes near a source. |
| **Hold** | `SHORT` or `EMPTY`: under a magazine it leaves the spot, buys and returns to it. | Keeps the spot at `LOW`, says nothing. |

In every order the trip begins only where the economy lets any errand begin: no dead within `CLEAR_FROM` (12 m), no
target in sight; a `LOW` reserve is filled only in a lull (a break, five zombies left or a quarter of the round, ten
seconds without a sight of the dead); under a magazine it goes in a round too, wherever the dead are not. So a bot
never walks through a horde for rounds. A trip begun gets four metres more leash, so a leader at the edge does not turn
the bot round on every step. The stand is the one with the shortest **walk** (`BotPath.walk_length`, asked of the legs
for the four nearest by the straight line, kept three seconds; a stand it cannot walk to is passed over), not the
nearest by the line, and the one the bot is heading to counts six metres nearer, so a trip does not change its mind.

**Adding a need (#693's health stances).** Add a key to `RULES` with a row for each order, a level function that reads
the bot (`BotNeeds.ammo_level` is the model: pure, the bot's own state in, a `Level` out) and, where the need is acted
on, one call to `BotNeeds.verdict`; `BotErrands._verdict` is the call for rounds. The brain has no branch for it.

**Proof.** `tests/bots/test_bot_needs.gd`: every cell of the table, the levels from the guns, what is near the leader,
the choice by walk (22 cases). `tests/night/test_bot_own_ammo.gd`, in the real lot with a person and a bot: Roam walks
to the locker that is the shorter walk (not the nearer one by the line, east of the concession's fence) and buys;
Follow stays and says it with no locker near, goes when the leader walks to one and comes back, and goes anyway with an
empty gun and comes back; Hold keeps the spot at `LOW`, leaves under a magazine and returns, and goes to a marked
locker at `LOW` (the ping wins). The film of a bot running low, walking to the locker, buying and coming back under each
order: `tests/captures/bots_own_ammo.tscn`.

**How it fits the ping rule (#670).** The ping names the place and wins over any order; the need names no place, takes
the nearest by walk and answers to the order. A ping to a bot that is not short is still ignored.

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
| **A human goes idle or leaves** | The bot does not wait for them in a fight; a Follow whose person has left is a Roam, and in a break it goes on errands. A human who leaves frees the slot for a bot (decision 7: a human who joins inherits it). |
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
  to it is a reviewed change. *Built (#225):* the hash is of each command's buttons, walking direction in eighths and
  view in 5 degree buckets, over a rig with no physics engine, because the last bit of a float differs between
  machines. *Measured:* two runs of the same commands in two world instances are **not** bit-identical: a body that
  walks differs by a hair (1e-5 m on its first step, then a different fight), and a zombie walks round an obstacle by
  either of two tied routes (0.75 m apart, in about a run in four). So the replay test seats bots that stand and fight
  (`retreat_margin = 0`) on the open field, compares the rules' state (the round, the dead left, each player's place in
  quarter metres, health, ammunition, points, kills) and leaves the dead's places out, and checks that a fight
  happened; it passed twelve runs in twelve ([lesson](https://github.com/Ryubara/gdstudio/blob/main/docs/lessons/2026-11-02-a-walking-body-makes-two-runs-of-the-same-commands-differ.md)).
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

**Measured on the built host (#225)**, same machine and rules as above (`BotClient`, regular profile, real ray tests;
the server steps at 60 Hz here, 16.7 ms a tick):

| What | Measured |
| --- | --- |
| A think (look with its rays, thought, hands), 0 / 10 / 30 / 46 zombies in the frame, 1,500 thinks each | p50 29 / 95 / 163 / 183 microseconds; **p99 76 / 170 / 275 / 290 microseconds** (best of three batches; at most 0 / 2 / 6 / 6 rays) |
| What a bot costs each 60 Hz tick in a four-player night (it hears its share of the events, decides, sends the command as plain data to `apply`), rounds 1 and 2 | about 85 microseconds: 20 to hear, 65 to decide and send (the motor runs every tick, a think one tick in 8) |
| The server's own step in the same night, four players and 7 zombies | 1.65 ms |

The 46 zombies are the rules' cap at four players (28 plus 6 for each extra player). The p99 is under the 0.5 ms
budget with room, and the test (`test_bot_night.gd`, scenario 26) scales the budget by how fast the runner runs a fixed
piece of GDScript, so a slow machine does not fail it. The first version of the look asked the light of every zombie in
the frame (the lamps are a list) and took 4 to 6 ms a think at 46 zombies; it now asks only the nearest few that pass
the angle and distance test, until the six rays are spent. Four bots cost about 0.35 ms of a 16.7 ms tick, 2%, before
movement and paths (phase 2) are added.

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
| Fires or throws into teammates | Any shooter | A grenade hurts its thrower alone (#856): none where its blast reaches the bot, under a tenth of its health at that spot (`BotGrenadier.harmless_apart`, 5.8 m; the blast hurts the thrower out to 8 m, #805), planned 7 m off. The bots keep no distance from teammates (nothing to protect), and keep out of their own live grenade ([#872](grenades.md#the-bots-and-their-own-grenade-872)) |

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
  `NightTuning.revive_reach` (2.0 m) of a downed teammate for `HealthTuning.revive_seconds` (3.5), with the reviver
  free to let go, step away or be struck down, which starts the time over. The frame carries `reviving` and `revive`
  (0 to 1) per player, the prompt `{kind: revive, id, progress}` comes before a door's, and `revive_started` and
  `revive_stopped` (reason `released`, `moved`, `down`, `done`) go to the clients. **No bleed-out in #511** (the 45 s
  clock came with #486, [Revive](../design/revive.md)), and **no points for a revive** (the rescue pay of the
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

**Built (#225).** Under `game/gameplay/bots/`, all `RefCounted` or `Resource` data in typed GDScript:

- **`BotClient`** is the host. It is given a `ClientState`, a `BotProfile`, a seed, a callable to send with and a
  `BotLevel` (the sight and lit callables, the rounds table and the navigation map), and nothing else; a test reads
  its `_init` and fails on any other argument. `hear(events)` lets the allow-list `BotEvents` through (public events,
  and a short list that count only when they are about the bot) and gives the state its own copy of the frame;
  `decide(delta)` makes the command and `tick(delta)` also sends it. After the perception has looked, the raw zombie
  list is taken out of the client state, so the brain and the motor can only read beliefs.
- **`BotPerception`** is the filter: a 110 degree cone around where the bot looks, a sight range that follows the
  light (`BotLevel.view_range`: 8 m plus 25 m times the round's ambient, or 33 m on lit ground), a ray from the eye to
  the chest and then the head, at most six rays a think (nearest first), a per-contact reaction drawn log-normal around
  the profile's mean and never under 0.20 s, a memory of three seconds that is never shot at, and hearing within 4 m
  as a direction and a range class (no position, no id). A contact seen for less than its reaction is dropped, except a
  zombie in its swing within 2 m (`ARM_REACH`), which is noticed from any side: out of the cone it was dropped at every
  think and its reaction began again, so dead swinging at a bot's back were never believed in (#695, seed 7).
- **`BotMotor`** (aim and trigger; movement is phase 2): a critically damped spring on yaw and pitch with a hard cap on
  the speed of the turn, so no 100 ms window beats `BotProfile.max_aim_speed`; the shot's `dir` is derived from the
  view (`NightCommand.look_along`), never the other way; seeded filtered tracking noise that grows with distance, the
  target's sweep and the bot's own speed and shrinks on target; chest or (at the profile's rate, slow and near) head;
  the trigger waits for the view to be inside the weapon's hit cone, with a seeded pause after each shot, bursts of
  three to five for an automatic weapon and a flick pause between targets.
- **`BotFightBrain`** is the brain of this phase (the fight only): nearest believed target with a commitment bonus,
  backs away inside the profile's margin, glances toward a blow or a sound, reloads and swaps. A **watchdog** in the
  client treats an answer that is not a sane `BotIntent` (what a script error in the brain gives) as a failure; at the
  profile's limit the brain is switched off, a `brain_disabled` telemetry event fires, and the motor holds where it
  stands and follows the nearest zombie it can see.
- **`BotProfile`** has `rookie()`, `regular()`, `veteran()` (the table above) and `autopilot()`. **The Autopilot is the
  first profile**: `Night` runs it through a `BotClient` whose `legacy` is the `Autopilot` object, which decides every
  tick from the whole frame exactly as before; the host only sends, counts and reports. Its own suites
  (`test_autopilot_night`, `_machines`, `_fuel`, `_switches`, the kill-allocation budget) pass unchanged.
- **`BotTelemetry`**: counters, named events, think-time percentiles, a ring buffer of the last 300 decisions with the
  beliefs behind them, a JSON report line, and a command hash (`signature`: the buttons, the walking direction in
  eighths and the view in 5 degree buckets, so it does not move with the last bit of a float). **`BotCoverage`** lists
  every shop item kind, weapon and prompt with a rule or a waiver naming the phase; a test reads the server's source
  for prompt kinds, so a new prompt without a bot rule or a waiver fails the build (scenario 28).
- **The harness** (`game/tests/`): `SeatedNight` (`NightFixture.seat`) builds the lot and the server with no client of
  its own, seats up to four players, puts a `BotHost` on them and sends every command through `NightServer.apply` as
  plain data. `BotRig` is a bot with no server, for the parts' own tests. Scenarios 1 to 3, 24 to 28 and the soak are in
  `tests/night/test_bot_night.gd`, `test_bot_soak.gd` and `tests/bots/`.
- **What the tests found.** A downed bot still sent a walk. The first perception looked up the light for every zombie
  in the frame and cost 4 to 6 ms a think with 46 zombies; asking the light only of the nearest few that pass the cone
  and range test brought it to the numbers below. And two runs of the same commands are not bit-identical once a body
  walks (see [Determinism and testability](#determinism-and-testability)).

### Phase 2: movement

Issue: #226.

Path following with a cache and a budget, door-rebake handling, unreachable memory, steering among 12 headings with mesh
projection, follow positions, yielding and gap rules, the stuck ladder with `bot_stuck`, curated `BotLink` markers.
**Done when**: scenarios 17 to 20 pass; a 20-minute soak of four bots shows stuck seconds under 1% of walking time and
no episode over 10 s on any seed; bots under the Follow order stay within 12 m of the person for 95% of a round (outside
errands; Roam and Hold have gates of their own, [Orders](#orders-follow-roam-and-hold-641));
no path error is printed across a soak with door purchases. **Tests**: the stuck detector on synthetic traces, the
follow scorer, a nav test on every area of the opening-order test, a negative control (a blocked gap) that the ladder
must solve or report.

**Built (#226).** Under `game/gameplay/bots/`, pure data in and a command out, time always the caller's:

- **`BotPath`** keeps one cached path and follows it with a look-ahead point (the first path point more than 0.8 m
  away; a corner run past at speed counts as reached once the bot is nearer the next point than the corner is). A goal
  is snapped with `map_get_closest_point` first; a goal the mesh does not reach is *unreachable* for 5 s and the brain is
  told, so the bot takes another errand and no question is asked twice. A door bought drops the cache and holds every
  query until the map's iteration id has moved (or a cap of seconds), because a query before the first
  synchronisation prints an `ERROR`. Three queries a second at most, per bot.
- **`BotSteering`** rates 12 headings (away from threats, toward the goal, room ahead, light, the nearest loop, the last
  choice) and projects the end of the best onto the mesh; a heading that ends off the mesh or that a wall stops is not
  a candidate, so a reflex cannot leave the mesh. **`BotFollow`** rates a ring of places round the people after Ellie (the
  band, the walk, behind or beside the leader, out of the line of fire, 2.5 m from the other bots, light, not in a gap),
  the cheap terms for every candidate and the ray and projection only for the best few, and keeps a place until another
  is clearly better.
- **`BotLegs`** turns the brain's goal or reflex heading into the way to walk: a person who walks at the bot is given way
  inside 1.2 m (or when closing in a gap), and **`BotStuck`** (a detector fed the commanded speed and the progress
  made, then the ladder: sidestep, repath to a jittered goal, jump, drop the goal, walk back along the breadcrumbs,
  `bot_stuck` report) never teleports. **`BotLink`** and the lot's loops are authored data read by `LotBotData`
  (the loops are rectangles 3 m outside the generator cage and the projection booth's floor; the lot has no jump
  links yet, phase 5 uses them).
- **Tests.** Unit: the stuck detector on synthetic traces, the path (cache, budget, doors, unreachable), the steering
  and follow scorers (`tests/bots/`); `tests/world/test_bot_navigation.gd` asks a path from the start to a point in every
  area of the opening-order test with each of its nine door sets (an open area is reached, a shut one is marked, no
  empty answer). `tests/night/test_bot_movement.gd` has scenarios 17 to 20 in the real lot, a gap the mesh does not know
  is shut (the ladder solves it or reports, with no teleport) and a bot pushed into a wall. `ErrorCatcher` (a `Logger`
  added with `OS.add_logger`) collects what the engine prints, so "no path error printed" is an assertion and not a
  hope; its own test proves it sees the unsynchronised-map error.
- **The soak** (`tests/captures/bots_move_soak.tscn`, a local or nightly run) plays the old autopilot as the person
  (it shops, opens the doors and fights) with four hosted bots and prints per bot walking seconds, stuck seconds, the
  longest episode, the distance from the nearest person, queries a second, think and legs cost, and what each stuck
  episode ran into. `test_bot_soak.gd` runs a short one in CI. Measured on the final code over seeds 1, 2 and 6
  (20 game minutes or the game's end, the players' health tripled so the night lasts): no `ERROR`, no `bot_stuck`
  report, the longest stuck episode 1.7 s (the limit is 10 s), **stuck 0.9 to 1.2% of the bots' walking time** (the
  target is under 1%: met on one seed of three; one bot reached 2.7% on a seed), within 12 m of the nearest person
  **94 to 95% of the time** (the target is 95%; round by round it runs from 82 to 100%), 0.5 to 0.9 path queries a
  second per bot (the limit is 3). Over half of the stuck episodes are a bot pressed against another bot while
  following; the next rung or the other bot's step clears them in about a second. Tuning that point and the think cost
  are a follow-up issue.
- **What the tests found.** A path point run past at speed was never "reached", so the bot turned back for it (the
  look-ahead now moves on once the bot is nearer the next point than the corner is). A navigation query is an engine
  `ERROR` on the frames before the map has taken its first mesh in or a swapped one, which a test can only see
  through a `Logger`, hence the hold on every query after a door. The soak's stuck cause report (what the bot touched
  when an episode began) showed that most episodes are bot against bot, not the lot's furniture.
- **Cost** (the soak: four bots, 40 ticks a frame on a shared machine, so read the second digit as noise): a think
  **p50 about 0.11 ms, p99 about 0.65 ms** with the follow rating and steering in it (the phase 1 budget is 0.5 ms
  worst per bot at 40 zombies, so this run is over it on a shared machine: see the follow-up issue), the legs
  **p50 about 20 microseconds, p99 0.08 to 0.2 ms**, and 0.5 to 0.9 path queries a second per bot.

### Phase 3: combat and ammunition

Issue: #227.

Target utility, weapon ranking and swaps, tactical reloads, melee fallback, grenades with the safety rule, boss
telegraph dodging and weak-spot aim, the special-round stances, leash and kill courtesy. **Done when**: scenarios 10, 12
to 14 pass; per-profile hit rate and head share fall in the `SimSkill` bands (Rookie to weak, Regular to average,
Veteran to strong); a four-bot night passes the first boss night in at least the share of nights the simulator
predicts for its skill (within 15 percentage points).

**Built (#227).** Under `game/gameplay/bots/`, small pure classes the fight brain calls (`BotFightBrain` is the one that
decides, the others hold a rule each, so a test pins them one by one):

- **`BotCombat`**: the target **utility**, in points, for a believed zombie in sight: its nearness (6 at the bot's
  feet, nothing at 25 m), a swing under way (+3), a runner (+1.2), the headliner once it is near (+1.5), how fast it
  comes at the bot (up to +0.8), a zombie on a teammate hit in the last 2 s (+2.5), on a downed one (+3.5) or on the
  bot itself after a blow (+2), a hurt bot's zombies at its feet (up to +3), the loss of damage the weapon in hand
  suffers at that range (up to -3: a shotgun does not pick the far ones) and a +1 for the target it already has.
  **Kill courtesy**: a zombie that a person (not a bot) is aiming at (within 7 degrees, from 25 m or less) and that is
  6 m or more from the bot and not swinging is left to them; with nothing else to shoot, the bot holds fire. The
  zombie's own health is not a term: a client does not know it (`zombie_damaged` stays off the allow-list; its test
  says so). **`may_melee`**: never a swing into three or more dead within 4 m, unless every firearm is dry.
  **`leash_allows`**: a chase goes no farther than 12 m from the nearest person (a bot of the team when there is
  none), unless the target stands within 3.5 m of a downed teammate. The brain uses it for the one chase it makes: a
  bot with a crowbar walks up to a zombie that is not coming to it (one at the boards, held by a hit), never into a
  pack.
- **`BotArsenal`**: a weapon is worth `WeaponWorth.sustained_dps` (reloads in) times the damage the range leaves it,
  the ranking the simulator's players use. A forced reload when the magazine is dry, except with a zombie within 4.5 m
  and another weapon loaded (the swap is quicker); a tactical reload under 30% of a magazine with nothing within 8 m,
  and a top-up under 70% when nothing is within 16 m; a swap to the loaded weapon that is 1.4 times better at the
  range of the fight (the simulator's `SWITCH_GAIN`) and to the crowbar when every gun is dry; the crowbar goes back
  to a gun that can fire. A held gun with nothing left (magazine and reserve) is put down for a gun that has rounds in
  reserve only, which is reloaded next (#695: the old plan held the empty gun for the rest of the night, kiting
  whatever followed it, because reload needs reserve in the held gun, swap needs a loaded gun and `dry` counts the
  other gun's reserve). `Plan.unloaded` (no gun can fire this moment) lets the quick melee fill the wait. A blade in
  hand with no gun loaded goes back to the gun that needs its reload once the nearest zombie is past 6 m
  (`RELOAD_GAP`); nearer, the bot is `cornered` and strikes with the blade, a pack of three or not (before, the pack
  rule forbade the swing, the swap back waited for 8 m clear, and a bot kited ten dead for 500 s with a fire axe in
  hand and a shotgun at 0/54).
- **`BotGrenadier`**: a grenade at a pack of three (two in Crawl Space) within 3 m of each other, 3 to 12 m away, as
  the pack will stand when the 3 s fuse runs out (it keeps walking), when the blast is 7 m or more from the bot (a
  blast that lands exactly there takes 2% of its health; the grenade lands a metre or so off, see the lesson on the
  rolling grenade) and wherever the teammates are (only the thrower takes the damage, #856; #872 took the old
  clearance away), with an open arc and 6 s since the last. The
  pitch comes from a table of real flights made once with `GrenadeArc` on flat ground: the heavy grenade (#680) lies
  4 to 12 m out and hardly rolls, so a short throw is a lob (underarm up to 4 m, steep overarm to 12 m). The plan flies
  the walls, and the dead where they will stand as the arc passes (`ZombieBump`): a zombie that would stop the real
  grenade nearer than 7 m from the bot drops it at the bot's feet, so the throw is not made (#872). The motor turns,
  holds the button for two ticks and keeps the view still while the arm swings; the brain takes the order back while
  the view still turns if a zombie comes within 3 m. From the order to the blast the bot keeps out of its own grenade
  (`BotFightBrain`): it steps out of reach, never takes a retreat heading toward it (`BotSteering.keep_out`), and
  within 20 m of it stands and fights (`blast_wait`) instead of following, chasing or running an errand.
- **`BotDodge`**: a swing that began on the frame (`attack_at` on the contact) and that would still reach the bot
  (within 1.4 + 0.4 m, plus 0.3 of drift) is stepped out of after the profile's reaction time, if there is time before
  the blow (0.45 s a plain zombie, **1.2 s the headliner**): a retreat heading on the mesh at a sprint. A telegraphed
  (boss) swing is made out with the profile's `telegraph_read` (0 for the Rookie, which never makes one out, 1.0 for
  the others; the simulator's `read` is a factor on the blow's chance to land, not a chance to see it, so the two are
  not the same number: [fitted in #568](#rookie-and-the-weak-boss-night)), rolled once a swing. The headliner is
  also kept `boss_keep` (6 m) away. The weak spot: the lit lens at
  (0, 1.16, 0.29) in the boss's frame, aimed at with the profile's `weak_spot_rate` when the boss faces the bot
  (`BotMotor.weak_spot`).
- **`BotStance`**: Midnight Stampede is `HOLD` (no retreat, no sprint; walk to a choke and stay), Crawl Space `LOW`
  (the aim already follows the crawler's height; a grenade needs only two) and Double Feature `BOSS`. A choke is the
  place within 4.5 m of the group (or of the bot) with the most walls about it (eight 2.5 m rays; at least three), two
  candidates rated a think, never a gap, kept until a place with a wall more is found. The special round is read from
  `round_started`'s `special_id`, which is public.
- **Tests that stood in the way.** The bot does not hear a round that began by a direct `rules.apply` (see the
  lesson); `SeatedNight.start_round()` hands the answer to the host.

**The bands test stages the dead (#783).** The bands were first read with the dead walking the lot to the bot, and
that reading belonged to the map as much as to the bots: the maintainer's 20 added field lamps (#719) took the
Regular's head share from 0.80 to 0.97 and halved the shots (321 to 173, 253 to 131, 140 to 99), with no change to a
bot. The lot's cars and posts decide where the dead come into view, so any map change moves the numbers. Measured
with the baked navigation meshes swapped, the same (the fight does not read them); with the new lamps taken out, two
of three levels back in band (the rest is the dead's route round the lot). The test now fights twice, on the shipped
map and unchanged by it: the **far fight** (`SeatedNight.stage_the_dead`, each zombie put once 10 to 16 m ahead,
walking straight at the bot, eight seeds of 50 s, the pistol, endless rounds and health) reads the hit rate and the
head share, and the **near fight** (the dead put 4 to 6 m ahead with the trigger up, `hold_fire`, eight seeds of
30 s) reads the dodge. A bot that fires at the dead put near kills them before they swing, at every spawn pace tried
(a zombie every 0.5 or 1 s: no blow on a Regular or a Veteran; every 0.2 s: 1,583 on a Rookie and 5 on a Veteran in
the same seconds), so the dodge is read from the legs alone. Local readings
(main and the maintainer's layout, commit 34867f29, agree):

| | Rookie (weak) | Regular (average) | Veteran (strong) |
| --- | ---: | ---: | ---: |
| Shots, 5 to 20 m (main / 34867f29) | 466 / 466 | 258 / 258 | 181 / 181 |
| Hit rate (level's number) | 0.40 (0.45) | 0.65 (0.65) | 0.76 (0.82) |
| Head share (level's number) | 0.61 / 0.61 (0.68) | 0.75 / 0.75 (0.81) | 0.88 / 0.88 (0.85) |
| Dodge, legs alone (band centre) | 0.00 / 0.00 (0.0) | 0.24 / 0.20 (0.3) | 0.65 / 0.64 (0.6) |

The bands stay `SimSkill`'s hit rate (plus or minus 0.12) and head rate (plus or minus 0.10); the dodge is a band of
its own (centre 0.0 / 0.3 / 0.6, plus or minus 0.2), because the dead pile up round a bot that does not kill them: it
reads lower than `SimSkill`'s 0.17 / 0.55 / 0.80, which is the chance that a blow misses a player who also shoots.
`SimSkill` did not move, so no balance batch was needed. The old numbers below are the ones the lot's route gave.

**Measured.** *Bands* (`tests/night/test_bot_bands.gd`; one bot with the pistol and endless rounds and health against a
stream of walkers at 2.4 m/s, about round 8; hit rate and head share from the shots at a zombie 5 to 20 m away, since
nearer a shot lands whatever the aim; dodge from the blows that came due on the bot, the share that missed; four seeds
of 110 s in the test, six of 150 s for the numbers below):

| | Rookie (weak) | Regular (average) | Veteran (strong) |
| --- | ---: | ---: | ---: |
| Hit rate, 5 to 20 m (level's number in brackets) | 0.41 (0.45) | 0.70 (0.65) | 0.86 (0.82) |
| Head share of the hits | 0.07 (0.06) | 0.15 (0.15) | 0.31 (0.30) |
| Dodge (of the blows that came due) | 0.08 (0.12) | 0.20 (0.30) | 0.51 (0.50) |
| Shots counted, blows that came due | 266, 278 | 314, 125 | 252, 55 |

The test holds each number to the level's number, a tolerance either side (hit rate 0.12, head share 0.07, dodge 0.15:
wide enough for the run-to-run difference of a physics engine and for the few hundred shots of a run, narrow enough to
keep the profiles apart).

*Boss night* (`tests/captures/bots_boss_night.tscn`, `BossNight`): four hosted bots of one profile play the first boss
night (round 5, two headliners among escorts at four players) in the real server. The bots cannot shop yet (phase 4),
so they begin the round with what the simulator's players carry then (the pistol and the crowbar, for 120 of 160
players of every skill), full magazines and a full reserve, and a bot that runs dry is given its rounds back after the
simulator's 8 s for a trip to the locker. A night passes when the round ends with a bot standing; it is lost when
every bot is down or 420 s of play pass. The simulator's prediction is the share of the nights that reached round 5
(300 nights, four players) that did not end in it:

| Skill | Simulator: passes round 5 | Bots, four of a profile | Inside 15 points |
| --- | ---: | ---: | --- |
| weak / Rookie | 0.40 (118 of 297 nights) | phase 3: 16 of 16 (1.00), and 16 of 16 with half the reserve; [fitted in #568](#rookie-and-the-weak-boss-night): 36 of 90 (0.40) | phase 3 **no**; #568 yes |
| average / Regular | 0.997 (299 of 300) | 16 of 16 (1.00) | yes |
| strong / Veteran | 1.00 (300 of 300) | 16 of 16 (1.00) | yes |

A night took 133 s (Rookie), 119 s (Regular) and 114 s (Veteran) of play. **In phase 3 the Rookie was not within
the band** (fitted since, below): the
simulator's weak players die in 60% of the boss nights they reach; four Rookie bots lost none in the 32 nights of the
final code and 5 of 64 earlier ones. Tried along the way, none moving the share under 87% in eight nights: a telegraph
read of 0.3 (the simulator's `read`, kept: `BotProfile.telegraph_read`), no keep-off from the boss, a narrower view
and shorter memory, a reaction of 0.9 s, half the ammunition. The bots are downed (up to three of four in a night) but
never all four, and they do not revive yet; the cause is more likely the lot (a long approach lane and a boss at 0.45
of the walking speed, which a bot walks away from) or the weak level's damage model than the bot's skill. Follow-up:
issue #568 (phase 7 fits `SimSkill` to the measured bots).

#### Rookie and the weak boss night

Fitted in #568 (`BotProfile.rookie()`), measured with `bots_boss_night.tscn --profile=rookie --topoff=0.5` on `main`
after #616. The aim was 25 to 55 percent of 30 nights; the simulator's number is 0.40. Four Rookies pass **13 of 30**
nights (seeds 1 to 30), **9 of 30** (seeds 101 to 130) and **14 of 30** (seeds 201 to 230): 36 of 90, 40%, and each
set of 30 inside the band. The Regular still passes 8 of 8.
The Rookie's bands test (`tests/night/test_bot_bands.gd`) still passes (3 of 3: Rookie hit rate 0.42, head share 0.08,
dodge 0.11). The view cone costs the head share (0.09 on `main` with 110 degrees, 0.13 with 80 or 90, the test's
edge), so the head-aim rate went from 0.07 to 0: the Rookie never aims at the head, and the level's 0.06 is what
the spread of its aim gives.

What moved the share, in nights passed (seeds 1 to 30 unless a smaller count is given; each a run of the capture with
`--set=`; the rows before the last three were made before #616 landed):

| Rookie | Nights passed |
| --- | ---: |
| as in phase 3 (`telegraph_read` 0.3, view 110) | 4 of 4, and 16 of 16 in phase 3 |
| never steps out of the boss's blow (`telegraph_read` 0) | 16 of 30 (53%) |
| `telegraph_read` 0.1 | 20 of 30 (67%) |
| `telegraph_read` 0 and `follows` off | 3 of 8 (`follows` off alone: 6 of 8) |
| `telegraph_read` 0 and `weak_spot_rate` 0.2 (the level's) | 19 of 30 |
| `telegraph_read` 0 and `weak_spot_rate` 0.1 | 10 of 18 |
| `telegraph_read` 0 and `think_hz` 3 | 9 of 17; 14 of 30 together with the view below |
| `telegraph_read` 0 and `view_degrees` 80 | 12 of 30 (40%); after #616, 9 of 30 and 10 of 30 on seeds 1 and 101 |
| `telegraph_read` 0, `view_degrees` 90 | 8 of 30 |
| `telegraph_read` 0, `weak_spot_rate` 0 | 29 of 52 (56%) |
| **`telegraph_read` 0, `view_degrees` 80, `head_rate` 0 (shipped)** | **36 of 90 (40%), after #616** |

The lever was the dodge. A Rookie that made out a telegraph (30%) stepped out of it and lost nothing, because the
boss walks at 0.45 of a walker's speed and the step was a sprint; a boss that never lands a swing cannot down four bots
in the 100 or so seconds it takes them to kill it. The simulator's `read` of 0.25 only multiplies the
chance of a blow landing by exp(-1.2 x 0.25) = 0.74 (a quarter of the blows miss, the rest land) and its players stand
still, so a bot that makes out one blow in three and dodges it whole is far stronger than the level's player. With the
Rookie never reading the telegraph the bots are downed in the nights they lose, all four, mostly with a boss still
standing (every lost night of the 16-of-30 run above had all four down; `NIGHT` lines now report `blows` by zombie
type and `boss_hits` by zone).

The simulator was **not** changed: its weak boss night is what the design wants (a spike, the weak players walled
until they learn the weak spot: [the balance page](balance-simulator.md#the-weak-boss-night-against-the-bots-568)).

*Cost* (a think, in the soak, four bots, shared machine): **p50 about 160 microseconds, p99 about 800** (seeds 1 and
2, eight game minutes, tough players, the autopilot as the person and four bots, a shared machine), against about 110
and 650 in phase 2: the target utility, the weapon plan, the dodge check and the pack count add some 50 microseconds a
think, and the p99 is over the plan's 0.5 ms (the same shared-machine caveat as phase 2; scenario 26 scales its budget
by the machine and passes). The grenade table (63 real flights for each style) is made once when the first bot is
built. #564 owns the think cost; nothing here tunes it.

**What the tests found.** The first calibration measured a hit rate of 0.9 for every setting of the aim noise (see the
lesson: the skill is in the trigger, and a hit at point blank says nothing about the aim); the proposal's retreat margin
of 5 to 9 m gave a dodge of 0.7 to 0.8, above the strong level, so the margins are 0 to 1.5 m now; every hit staggers a
zombie, the boss included, so a bot that shoots a boss in front of it is not dodging anything (the dodge test holds the
bot's trigger and counts only the swings that ran their course); a flat grenade throw lies 17 to 26 m out; and a
test counter in a lambda read zero.

**Left for the later phases.** Callout lines for buying (phase 5, with `bot_say`). The shopping parity above is for the
phase 7 fit (#231). The think cost of the errands was not separated from the machine's noise (a soak with and without
them printed the same p99, 3.5 to 3.8 ms on a loaded machine); #564 owns it.

### Phase 5: team play, revives and edge cases

Issue: #229.

Roles as stances, the claim table, the risk check, clear-then-revive, commit and abort, last-standing logic, trapped
logic, callouts and human pings. **Done when**: scenarios 4 to 7, 15, 16 and 23 pass; in a soak of four bots against
the real zombie mix, revive success is at least 70% of attempts and `deaths_reviving` under 10% of attempts; no more
than one bot at a time on an errand; the callout rate is under one line per bot per 10 s and none names an unseen
zombie.

**What shipped in part 1 (the revive; callouts, roles, the errand turn, trapped logic and pings are part 2).**

- `BotReviveRisk` is the risk check as a pure function. The window is the walk there (the straight line stretched by
  1.2 at 4.2 m/s), the 3.5 s hold and a margin (2.0 s cautious to 0.6 s bold by `revive_eagerness`). A zombie threatens
  when it can reach the body or the reviver inside the window (speed from the round's public formula, the dark's
  1.25 in full, the type's share from a table a test holds to the roster). Verdicts: `SAFE`; `CLEAR` (the dead that can
  arrive can be killed in 7 to 16 s of the held weapon's sustained damage, `WeaponWorth`, times a 0.55 hit share, and
  there are at most 5 to 12 of them); `UNSAFE` (more or tougher: a pack, the boss); `LATE` (the bleed-out clock is
  shorter than the walk).
- `BotClaims` is the claim table: bids of distance each think (1 s), the nearest takes the claim, ties to the lowest
  seat, a 3 s lease renewed every think, a challenger must be 2 m nearer to take one and never takes one whose holder
  is in its hold, and a seat that is released frees its claims at once (`BotHost.release`, scenario 23). The host
  hands one `BotTeam` to every bot it seats, as it does the roster.
- `BotRevive` is the behaviour. The reviver is `GO` (walk, run), `HOLD` (hold `use` within 1.6 m of the body; no shot,
  swap or reload), or `CLEAR` (fight from within 7 m of the body, the zombies nearest the body first). The others are
  `COVER` (stand within 4 m of the body and shoot the zombies nearest it first). The last one up with someone down
  and the risk not clear is `SURVIVE`: no approach, a 5 m retreat margin (a downed player gets up at the round's end,
  and the night is over when all are down). The walk is judged with the eagerness raised by 0.35, so a zombie that
  shows up on the way does not turn it round at once; the hold ends only by the abort rule (more than one zombie on the
  bot and 20 health lost in a second, or under 30% health; past 60% of the hold only the health), then the bot clears
  and retries after 1.5 s.
- A bot at the revive faces the body, so what hits it from behind is only *heard*: the count of zombies on the bot is
  the larger of the believed ones within 2.5 m and the ones heard very near.
- Telemetry: `revive_attempts` (a hold begun, from `revive_started`), `revive_successes` (`player_revived` with the
  bot as reviver), `revive_aborts` (the rule), `deaths_reviving` (`revive_stopped` for the reason `down`).

*Measured* (`tests/captures/bots_revive_soak.tscn`, four mixed bots, no person, the shipped zombie mix and health, a
seeded player put on the ground every 20 s while two others stand so that the revive is tried in the middle of the
fight, 12 game minutes, seeds 1 to 3, a shared machine): **99 holds begun, 92 raised (93%), 4 let go of by the rule,
no bot went down while holding**; 94 of the falls were made by hand; two falls bled out with nobody raising them (seed
3, a bot that was in a pack of the dead). Without forced falls the shipped mix rarely downs a bot before round 10
(eight game minutes, none; at 35% health the four bots go down within 90 s and the night is over, so that is no
measure of the revive). The scenarios (`tests/night/test_bot_revive.gd`) hold 4 to 7, 16 and 23; the risk function and
the claim table have pure unit tests; a mutant that makes the risk check always say `SAFE` fails scenario 5.

**What shipped in part 2 (the team: errand turn, roles, callouts, trapped logic, pings).**

- `BotTurn`: one bot at a time goes on an errand (the maintainer). A bot asks before it goes and says it went on every
  think of the errand; the turn lapses a second after the last time, so a bot that finished or was called to a fight
  gives it up at once, and a bot that kept it 30 s while another waited rests 10 s. `BotTeam.one_errand_at_a_time`
  turns it off (the soak's `--parallel`), to measure what it costs.
- `BotRoles`: anchor (the default, at least one for each person), flank (with a person and one bot more than there
  are people, one bot holds a choke 11 m to the side of the people's heading, `BotStance.choke` rating the place) and
  maintainer (whoever has the errand turn). Reassigned every 3 s, kept 10 s, one table for the team.
- `BotSay` (twelve enumerated lines with their words and cooldowns of 20 to 60 s), `SayBoard` (the server's gate, one
  line a player every 4 s, so a bot that misjudges itself cannot flood the feed) and a new `say` action answered by a
  `bot_say` event that the feed shows ("NAME: RELOADING!"). `BotCallouts` decides what a bot says from what it
  perceived: the boss or three runners it believes in (a line about a zombie is refused unless the zombie is a
  believed contact), a reload with the dead near, a revive begun, the bot asking for cover when hurt with two on it,
  thanks after a revive, a door bought, the generator low (one bot speaks for the team), a breach open, rounds
  running low in a lull, being boxed in, and one call for help when it is down. Each line has its cooldown, a bot has
  a gap (12 s, 5 s before an urgent line) and no more than two lines in any 25 s, so the rate is bounded by
  construction: under 0.8 a line per bot per ten seconds. (Voicing the lines is left for the audio work.)
- `BotTrapped`: no free heading for two seconds on end (`BotSteering.pick` finds none) is trapped: the bot fights on
  (nothing else changes), says so once, writes a `bot_trapped` event and, if a curated place to jump from is within
  8 m (`BotLink`), goes there and jumps (`BotIntent.trapped`, in the legs). There is no teleport.
- `BotPings`: a person's `here` sends the nearest bot to hold the place while the mark stands, `enemy` names the first
  target while the bot sees the zombie, `downed` names the body to raise first, `door` is the errands' (it was
  already). `ammo` is the next item (#647, below).
- **The ammunition ping (#647).** `BotPings.ammo` reads the locker a person marked. A bot that is short of rounds for a
  gun it carries (under `BotProfile.ammo_floor_mags` magazines of reserve), in a lull, with the gun (or a blade, which
  is put away at the locker) in hand, walks to *that* locker and buys there, before every other errand (`BotErrands`
  runs a `marked` job ahead of the generator, the breakers, the shop list and the boards; a mark lasts 20 s and a bot
  that set out keeps going for at most `ERRAND_LIMIT` if it runs out on the way). It buys only within the use reach of
  the marked locker: every locker sells the same rounds, but a mark is an order for one, so a bot standing at another
  locker walks on. A bot that is not short, whose hand cannot be fed there (the locker sells for the weapon in hand), in
  a wave with the dead about it (the urgent rounds below a magazine are still bought at once, wherever) or with no way to
  the locker (the shop's own `avoided` rule) ignores the mark. Pure table:
  `tests/bots/test_bot_economy_rounds.gd`; scenario in the real lot with a person and a bot, and the same bot with no
  mark going to the near locker: `tests/night/test_bot_errand_buys.gd`; film through the person's camera:
  `tests/captures/bots_ammo_ping.tscn`. The ping crosses the wire as before (`NetWire.Type.MARK`, no new message), so
  no network test was added. Two bots that are both short both go (rounds are personal); the errand turn of the brain
  still lets one bot at a time leave.

*Measured* (same soak, 12 game minutes, seeds 1 to 3, a shared machine on which every think p99 was 5 to 40 ms, so no
cost figure is taken from it): **at most one bot on an errand at any tick in all four runs (the same soak with the
turn off had all four at once); 62 to 80 callouts a night, 0.28 to 0.38 a bot per ten seconds**, and the revive
numbers held (seeds 1 to 3: 24, 25 and 24 holds, 23, 23 and 19 raised, 4 let go of by the rule once, one bot down
while holding in one run). **The turn costs something**: on the same three seeds two nights of three end before 12
minutes with the turn (round 6 at game seconds 498 and 609; the third is at round 6 when the time is up), two of three
with the turn off (rounds 7 and 6 at 556 and 503 seconds; the third at round 8), and one of three on main without any
of this part (round 6 at 527 seconds; the others at rounds 8 and 7): three seeds of a chaotic night say a round or so,
not more, and the fit work (#231) owns the parity. The roles, the pings and the trapped logic did not engage in these
no-person soaks; their scenarios (`tests/night/test_bot_team.gd`, `tests/bots/test_bot_trapped.gd`,
`tests/bots/test_bot_pings.gd`, `tests/bots/test_bot_roles.gd`) hold them. Scenario 15 is a pocket the rig makes
(every low ray is a wall, the eyes see over it): a lot corner with no way out was not found on the real mesh, so the
real-lot check is that no bot moved more than a metre in a tick over the soaks (the most was 0.64 m).

**What shipped in part 3 (the flare, #646).**

- **The rule** goes through the claim table like the revive, not a second path: only the bot that holds the claim on a
  body can order a flare (`BotRevive`, mode `LURE`), under every order a bot has. It is considered when the verdict is
  `CLEAR` or `UNSAFE`, the bot carries a flare with a round (in the magazine or in reserve), no flare is burning or was
  just fired (4 s apart), no dead is within 3 m of the bot, at least two of the dead that threaten the window are ones a
  flare draws (not a boss, not a zombie in the middle of a swing), and drawing them off would make the revive better:
  judged again with those dead standing 12 m from the body and starting for it only when the lure is out, it must be
  `SAFE`, or `CLEAR` where it was `UNSAFE`. A bot that would have been left out of the claim for an `UNSAFE` body bids for
  it when it has a flare shot; one that is not the claimant never plans one.
- **`BotFlare`** finds the shot (pure: positions in, a `Shot` out, or null). The flare is direct fire at what the view
  meets, so the lines worth trying come from a table of flights made once with the real projectile and aim correction
  on flat ground (24 headings, 10 to 22 m out, the nearest the bot may fire and the farthest it may hit), kept to the
  spots at least 12 m from the body and 6 m from any player, off the reviver's side of the body (60 degrees at the body),
  within the lure's reach of every zombie to be drawn, and not drawing them past the bot. The best are then **flown for
  real** (the server's `ProjectileState` and `AimResolver` in the bot's own world: the walls the level can see and the
  dead it believes in) and the rules are asked of where the flare lands, not of where it was aimed: at least 8 m from
  the bot, 10 from the body, 5 from every player, the dead within 24 m of it; and again with the view turned a little to
  each side. A heading where the flare came up short (a car) shuts its neighbours for this plan; a plan that finds
  nothing waits a second.
- **The hands.** `BotIntent.flare_yaw`/`flare_pitch` order a flare: the motor turns to that view (a ground point, not a
  zombie), pulls the trigger once when the view is within a degree, and never fires the flare gun at a zombie.
  `BotRevive` swaps to the flare gun (reloading it first when its round is spent) and stands still; the brain gives the
  weapon handling to it for the order. `BotArsenal` puts the flare gun away for a loaded gun as soon as no flare is
  ordered, and the flare gun is no firearm for the fight (a bot with only it is `dry` and uses the quick melee). An
  order is given up when its round has flown, after 5 s, or when a dead gets within 3 m or a player near the landing.
- **The risk check knows the lure.** A bot hears the burst of its own flare (`lure_started` is in the `OWN` allow-list)
  and the team keeps it (`BotTeam.lures`: point, radius, until). The dead within its radius count as standing at the lure
  with its remaining seconds as a `delay` (`BotReviveRisk.Threat`), so the revive judged after the flare is `SAFE`
  while it burns and a bot walks in and holds. `BotCoverage` lists the rule; telemetry counts `flares_wanted`,
  `flares_no_spot` and `flares_fired`.

*Measured.* The scenario (`tests/night/test_bot_flare.gd`): a person down, eight of the dead about the body, the bot with
three rounds, no grenade and the flare gun. It fires, the flare bursts well away from the body and the dead walk to
it, the hold begins after it with no blow on the bot and the person is raised; the same night without the flare gun
has the pack uncleared and the person still down 40 s on (the bleed-out clock is 45 s); a mutant that never fires
fails the first. The soak (`tests/captures/bots_revive_soak.tscn`, four mixed bots, forced falls every 10 s, 12 game minutes,
both runs carrying the flare gun and only the rule switched, `--no-flare-rule`, seeds 1 to 6, a shared machine):
**with the rule 256 of 280 holds raised (91%), 3 let go of by the rule, 3 bots down while holding; without it 263 of
298 (88%), 9 let go of, 4 down while holding**. The rule fired 18 flares in the six nights: it was wanted 47 times and
found no shot 26 of them (the cars; [the lure notes](flare-lure.md#bots-fire-it-646)), so it touches a few revives a
night and a difference of three points in a night's worth of chaos (the nights end at different times, 460 to 720
seconds) is not one to take to the bank: what the soak says is that the rule changes nothing for the worse in the
revive numbers. Bleed-outs were 17 with it and 10 without out of about 280 forced falls each. The one night read through
(`--log`, seed 1 with the rule: five of them) has none near a flare: they are bodies that two bots left alone for 45 s
while the dead stood about them (a verdict of `UNSAFE` sends nobody unless the bot is the last up), which the bots did
before this rule too; it is #673.

**Left for later.** The voice of the lines, and the bot's own "downed bot waits for a human" being only one call.

### Phase 6: filling slots, difficulty and the server

Issue: #230 (the room setting and the seating came first, with #643).

**What shipped.** The room's **Bots** setting (0 to 3, #643; 0 to 7 since #690 with eight seats) and a **Bot skill**
setting (rookie, regular, veteran) fill the empty seats of a night, for Solo and for a host's room alike, in [Rounds,
points and fuel](../design/rounds.md#bots). It is not the "off, fill to two, fill to four" of the first draft: the
count is the host's, and the server's own limits sit above it.

| Part | How it is built |
| --- | --- |
| Slot filling | `NightBots` seats bots in the highest free seats up to `target(setting, people, limit)`; a person with no free seat takes the lowest bot's seat as it stands (`hand_over`, `bot_replaced`), and **a person who leaves hands the seat to a bot as it stands** (`adopt`, `bot_seated`: the same body, points, weapons and health), so decision 7 holds both ways |
| Difficulty | `MatchSettings.bot_skill` picks the `BotProfile` of every bot (`BotProfile.for_skill`); the rules never read it, a test holds the night's numbers equal across skills |
| Names and looks | `BotRoster`: a cast of eight per skill, one per seat (Pip, Dale, Moe, ...; Ash, Fern, Moss, ...; Rex, Sarge, Hawk, ...; #690), each a name and a different catalogue preset look sent through the look server like a person's; the lobby shows the same names before the night begins |
| Labels | `BOT` after the name in the HUD, the scoreboard, the lobby and the feed; `PlayerState.bot` rides every snapshot, so the roster API marks the seat; no bot flag exists in a command (the bots send the same plain actions through `apply`, and a person's seat is told apart only by the rules) |
| Limits | `MAX_BOTS` caps one room (0 to 7 since #690, with eight seats), `BOT_BUDGET` shares a number of bots among the open rooms, `BOTS_OFF` is the kill-switch; a limit that drops sends the highest seats' bots away at once and the night goes on (`BotLimits`, `GameServer.set_bot_limits`, `NightHost.set_bot_limit`) |
| Marked in the stats | the room's stats line carries `bots`; the rules mark every bot seat, so nothing that reads `player_added.bot` can pay a bot account progression (there is none yet) |

**Proof.**

- **Ten minutes over the real transport** (`tests/captures/bots_slots_soak.tscn`, its own CI job `bots-soak`, two
  scenarios of ten game minutes each at `--fixed-fps 60`, about three and a half minutes of wall time). `pair`: two
  autopilot clients and two bots, round 7 reached, 36,000 ticks, the worst predicted body 0.70 m from the server's
  (the limit is 2.5 m), 1,191 seat checks with no client showing a seat the server did not hold, no stuck episode, no
  engine error in the verbose log. `churn`: a setting of 3, people join at 0, 10, 30 and 50% of the run and leave at
  70, 80 and 90%; the bots were 3, 2, 1, 0 and then 1, 2, 3 after each change as the rule says, the night was never
  rebuilt, the round never went back, and the three people who took a bot's seat kept its body and its kills.
  The server's step (the server, two clients and two or three bots in one process) averaged 1.4 to 1.5 ms of the 16.7 ms
  tick and its worst step outside a client joining was 9.9 ms.
- **The bots' own cost** (`test_bot_server_cost.gd`, a test): three bots with 40 zombies on the lot, 900 ticks, the
  part of the tick that is theirs (hearing the step and deciding). Measured on a loaded machine that ran the reference
  piece of GDScript 1.6 times slower than the machine the budget was set on: **mean 628 microseconds a tick (3.8% of a
  60 Hz tick), worst 1.25 ms**. The budget it holds, scaled by the machine's speed: mean under 5% of the tick, worst
  tick under 1.5 ms (a half millisecond for each bot's think). Scaled back to the reference machine the mean is about
  2.3%. After main's flare rule landed the same test reads a mean of 780 to 970 microseconds (5 to 6% of the tick on
  that machine, 1.5 to 1.7 times slower than the reference), a 95th percentile of 1.2 to 1.6 ms and a 99th of 1.8 to
  3.4 ms. The test judges the 95th percentile (budget 1.5 ms scaled) and prints the 99th and the worst tick, which on a
  shared machine is a tick the scheduler took (3 to 70 ms with the flare rule on and off alike, the median unchanged
  at about 0.73 ms); the budget of the 99th percentile failed under load from other jobs, as did the decision-cost
  scenario 26 of `test_bot_night.gd`.
- **The test failed on `main` from #744 to #771, with a real cost, not a tight budget.** Same machine and session,
  five alternating runs of `test_bot_server_cost.gd` on each commit: the commit before #744 (`b7dffa62`) read 697 to
  741 microseconds mean, #744 (`7538779b`) 1,577 to 1,631, `main` at the time (`82eac9bd`) 1,323 to 1,511 (8 to 9% of the
  tick, 95th percentile 3.2 to 3.5 ms), and the fix 647 to 705 (3.9 to 4.2%, 95th percentile 0.93 to 1.0 ms); the commit
  of the test (#715) read 645 to 815 in the same session. The cause: #744 made a bot with an empty gun strike with the
  quick melee, and `BotMotor` asked `WeaponCatalog.quick_melee().melee_range` on every tick of such a bot. The definition
  is a `.tres` that nobody holds until the server's first quick melee, so each ask read the file again, 0.8 ms
  (`quick_melee()` 797 microseconds a call unheld, 2.7 held). The motor now reads the reach once. The motor's own
  95th percentile went from 1,036 to 30 microseconds; the think (p50 about 400 microseconds with 40 zombies in view,
  `bots_move_soak.tscn --shop`: p50 240 to 300, p99 1.0 to 1.9 ms) did not change, so the soak's think numbers do not see
  this cost, which is in the motor. The budget stays at 5% and 1.5 ms.
- **The seating, skill and limits**: `test_room_bot_slots.gd` (a room over a socket: the skill names, dresses and drives
  the bots; a cap; the kill-switch at the start and thrown mid-night and lifted; a budget shared by two rooms; a person
  leaving hands the body to a bot and a third person takes it back), `test_night_bot_skill.gd`, `test_bot_limits.gd`,
  `test_bot_roster.gd`, and the rules' tests.

### Phase 7: validation at scale and tuning

Issue: #231.

#### The nightly soak and the parity batch

**What shipped.** `game/tests/captures/bots_soak.tscn` plays whole nights of hosted bots in the real server (the lot,
the rules and the zombies; the bots shop, fight and revive; ticks are run by hand with no clock), one cell at a time: a
profile, a team size, an order, and with or without a stand-in for a person (the old autopilot). Each night prints one
`SOAKNIGHT` line of plain data: the round reached, the gates it broke, and for each bot its shots, hits, heads, kills,
downs, revives, points by category, stuck and idle time, and the think cost. `SoakWatch`
(`game/tests/bots/soak_watch.gd`) reads the night from outside the bots (the server's events and positions, never a
bot's beliefs) and holds a night to the gates; `tools/bots/soak_report.py` runs the cells in chunks of a few nights per
Godot process, rebuilds the balance simulator's matching cell (`balance_cli.gd`, 300 nights), and writes `report.json`
and `report.md`: median round, the Kolmogorov distance of the two survival curves, the measured numbers of each profile,
and the gates each cell broke. `.github/workflows/bots-nightly.yml` runs it every night at 03:17 UTC, 100 nights for
each of the 12 cells in jobs of ten nights, and its last job fails when a gate is broken and writes the report to the
run's summary.

```text
uv run python tools/bots/soak_report.py run --out <folder> --set parity|orders|all --nights 100 --jobs 3
uv run python tools/bots/soak_report.py merge --out <folder> --gate        (read the chunks again; exit 1 on a broken gate)
godot --headless --path game res://tests/captures/bots_soak.tscn --fixed-fps 60 -- --profile=regular --bots=4 --nights=5
  ... --watch=SEAT --from=TICK --every=TICKS     (a line of what one seat is doing, for finding out why a gate broke)
```

**The cells.** The parity batch is each profile (Rookie, Regular, Veteran) with 1, 2 and 4 bots alone in the lot,
against the simulator's weak, average and strong cell for the same number of players (a room with no person is Roam,
which is what a bot does with nobody to follow). The order soaks are a person stand-in with three Regular bots under
Roam, Follow and Hold. A night is stopped when it starts the round cap (16 in the report below, 20 in the nightly run;
in the bots and in the simulator alike, a night that starts it counts as reaching it), when it has run 45 game minutes,
or when one round has gone on for 8 game minutes (a stalled round, below). A night is 40 to 130 s of wall time for one
to four bots on an idle machine (a game minute takes 5 to 8 s).

**The gates, and how each is read.**

| Gate | Read as |
| --- | --- |
| No engine `ERROR` | An `ErrorCatcher` (a `Logger`) is installed for the night; any line fails it |
| No stuck episode over 10 s, stuck under 1% of walking time | The bot's own telemetry (`longest_stuck`; stuck over walking seconds). The share is judged over a cell, not a bot: one five-second episode in a four-minute walk is 2% |
| No bot idle with a zombie in view for over 5 s | A zombie it has made out within 12 m, and the same command (`BotTelemetry.signature`) sent tick after tick with the body standing, no shot, no use. A zombie that comes a metre nearer while the bot waits ends the count: a dry bot or one with a crowbar waits for the blow where it stands |
| Follow only: no bot beyond 25 m of the person for over 20 s outside an errand | The server's positions; an errand is a bot whose note is buy, fuel, breaker, boards or crane |
| Roam: no bot standing with nothing to do (note roam, hold or none) over 8 s | The body's speed under 0.05 m/s |
| Hold: within 3 m of the spot for 92% of the time under the stance | Not on a trip for a revive, a ping, a dodge or an errand; the 1% stuck share is not asked of a bot holding a spot, which walks a few seconds a night |
| No rejected-buy loop | The same item refused to the same bot twice inside 29 s |
| No round that will not end | A round over 8 game minutes. New in this phase: see below |
| Parity | The median round within 1.5 of the simulator cell's, and a Kolmogorov distance of the two curves under 0.2 |

The gates that need people (`--person`) are only asked of the cells that have one.

#### What the soak found

Read from the first nights, in the order they were found; each is why a gate exists as it does.

- **A bot stood with an empty gun while another held its rounds in reserve** (`rifle [0, 24]`, a shotgun at `0/0`, a
  boss fight). `BotArsenal` swapped away from a dry gun only to a loaded magazine or a crowbar. It came out as bots idle
  with a zombie in view and as four Regular bots reaching round 9 (the simulator's 15); with the swap fixed (four nights
  each), kills a bot-minute went from 3.7 to 6.0 and the median round from 9 to 12. #744 landed the same fix while this
  was being built, so main's is the one in the code; the unit test of the case stays. Lesson in the kit
  (`a-bot-stood-with-an-empty-gun`).
- **Bots with thousands of points and no round left, in a round that did not end.** After main's own ammunition rule
  (#730) the bots still shopped only when the nearest dead one was 12 m away, and in a boss fight or a late round it
  never is: five of eight Regular nights (seeds 31 to 38, in the first boss night and the one at 15) stalled with the
  headliner alive for five minutes, bots without a round holding 400 to 11,000 points. A bot with no round left now
  **runs** for rounds (and for nothing else) with the dead 4 m away or more (`BotErrands.dash`, `DASH_FROM`), under any
  order. The same eight seeds: **0 stalled**, seven reached round 16
  (`test_a_dry_bot_runs_for_rounds_with_a_dead_one_in_sight_but_not_in_reach` fails without it). The soak counts a round
  over 8 game minutes as a gate broken (a night of 45 game minutes in a single round was the first sign).
- **The Rookie fell out of its fit.** #568 fitted the Rookie to the simulator's weak level (the first boss night passed
  in 40% of nights); after main's play states (#739, a hurt bot goes Careful and then Safe and backs away) and the
  ammunition and reload fixes it passed 30 of 30. A Rookie now **does not manage its health** (`careful_below` and
  `safe_below` 0, `BotProfile.rookie`): 9 of 30 (3, 4 and 2 of ten nights, seeds 1, 101 and 201), inside the 25 to 55%
  band the fit asked for; and again after main's #766 and #749, 16 of 30 (7, 6 and 3) with the change against 29 of 30
  (10, 9 and 10) without it. Tried and left: a Careful state from 30% of health and a Safe one from 15% (10 of 10), and
  the same with a track error of 20 degrees (3 of 10, no better than the one number).
- **The Regular fell out of its fit the same way (#768).** Eight nights a cell at cap 20 on the code before this change:
  Regular median 19, 19 and 18 rounds for one, two and four bots against the simulator's average level at 15, 15 and 17
  (Kolmogorov distance 0.85, 0.59 and 0.44; five of eight single-bot nights reached the cap). The play states of #739
  (a hurt bot backs away) are what a Regular did not have when it was fitted, and no player in the simulator manages
  health. A **Regular does not manage its health either** (`careful_below` and `safe_below` 0, `BotProfile.regular`;
  the play-state tests use the Veteran): medians **14, 17 and 16** against 15, 15 and 17 (distance 0.35, 0.32 and 0.43).
  Tried and left, one number at a time on the same eight nights of one Regular: a track error of 8 degrees (5 of 8 at
  the cap, the stampede of round 10 kills two or three either way), a reaction of 5 (3 of 8 stalled), a fire slop
  (4 of 8 over round 18). The Veteran was left as it is: median 17, 20 and 18 against the strong level's 19, 20 and 20.
  On other seeds (21 to 32, twelve nights, cap 20) the Regular reads median 16, 15 and 16 against 15, 15 and 17
  (distance 0.39, 0.22 and 0.48; four and ten nights of the four-bot cell and the first Veteran nights were in when this
  was written, the Veteran's one-bot median 20 against 19).
  The distance of two curves from eight nights has a noise floor near 0.5, so the 0.2 gate is read on the nightly run's
  hundred nights, not here.
- **A soak that measures what the bot does must not look at what the bot believes.** `SoakWatch` reads the server's
  events and bodies; the bots' beliefs are used only to say that a zombie was in sight, which is the gate's own word.

#### Measured

Eight nights a cell on the code of this change merged with main at the hit zones that follow the bodies (#749), the
simulator's retune (#766) and the bodies that pass through each other (#763): seeds 1 to 8 for a cell, 300 nights of the
simulator (seed 1), round cap 16, a machine shared with other work (so read wall times as an upper bound). The curves
of the bots and of the simulator are `parity.png` of the report.

**Parity with the simulator** (bots alone, Roam; the bots' median round against the simulator's cell, the Kolmogorov
distance of the two curves, and how many of the eight nights reached the cap):

| Cell | Nights | Median round | Sim median | Gap | Kolmogorov | Parity | Capped |
| --- | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| rookie x1 (sim weak) | 8 | 7 | 5 | 2 | 0.34 | NO | 0 |
| rookie x2 (sim weak) | 8 | 10 | 5 | 5 | 0.77 | NO | 0 |
| rookie x4 (sim weak) | 8 | 9 | 5 | 4 | 0.52 | NO | 0 |
| regular x1 (sim average) | 8 | 16 | 15 | 1 | 0.89 | NO | 8 |
| regular x2 (sim average) | 8 | 16 | 15 | 1 | 0.59 | NO | 7 |
| regular x4 (sim average) | 8 | 16 | 16 | 0 | 0.34 | NO | 8 |
| veteran x1 (sim strong) | 8 | 16 | 16 | 0 | 0.02 | yes | 7 |
| veteran x2 (sim strong) | 8 | 16 | 16 | 0 | 0.05 | yes | 8 |
| veteran x4 (sim strong) | 8 | 16 | 16 | 0 | 0.00 | yes | 8 |

Six of nine cells are inside the median gate (1.5 rounds) and three of nine inside the curve gate (0.2). The Veteran
matches the simulator's strong level from one bot to four. The Regular is within a round of the average cell's median,
and its curve is not the model's: seven or eight of its eight nights reach round 16 where the model's average player is
down by degrees from round 5 (the curve distance is 0.34 to 0.89), so a room filled with Regular bots is easier than the
model's average team ([#768](https://github.com/Ryubara/deadnight/issues/768)). The Rookie is two rounds better than the
weak level alone and four or five in a team ([#767](https://github.com/Ryubara/deadnight/issues/767)). The gate for each
is a failure of the nightly only with `--gate-parity`, which waits for those two issues.

**What each profile measured** (shots that land of the shots fired, heads of the hits, kills and downs for the bots in
the cell, revive success of the tries, points spent over earned against the simulator's cell in brackets, and the stuck
share of walking time):

| Cell | Hit rate | Head share | Kills per bot-minute | Revive success (tries) | Downs per bot-hour | Spend ratio (sim) | Stuck share | Wall s a night |
| --- | ---: | ---: | ---: | --- | ---: | --- | ---: | ---: |
| rookie_1 | 49% | 62% | 4.28 | n/a | 6.2 | 0.81 (0.70) | 0.00% | 20 |
| rookie_2 | 58% | 68% | 5.91 | 87% (15) | 9.6 | 0.65 (0.73) | 0.04% | 58 |
| rookie_4 | 60% | 62% | 5.02 | 87% (54) | 14.9 | 0.54 (0.72) | 0.05% | 98 |
| regular_1 | 74% | 76% | 9.78 | n/a | 0.3 | 0.74 (0.64) | 0.08% | 58 |
| regular_2 | 74% | 73% | 8.23 | 100% (3) | 0.9 | 0.68 (0.69) | 0.04% | 94 |
| regular_4 | 76% | 72% | 6.85 | 89% (9) | 1.0 | 0.68 (0.71) | 0.14% | 180 |
| veteran_1 | 82% | 83% | 10.10 | n/a | 0.3 | 0.67 (0.55) | 0.14% | 50 |
| veteran_2 | 81% | 79% | 8.52 | 100% (4) | 0.7 | 0.67 (0.57) | 0.16% | 87 |
| veteran_4 | 84% | 73% | 7.09 | 100% (6) | 0.5 | 0.69 (0.54) | 0.07% | 156 |
| regular_3_roam_person | 74% | 72% | 6.24 | 84% (19) | 0.9 | 0.71 (n/a) | 0.06% | 164 |
| regular_3_follow_person | 73% | 73% | 5.49 | 100% (8) | 2.1 | 0.66 (n/a) | 0.35% | 187 |
| regular_3_hold_person | 66% | 60% | 3.12 | 100% (5) | 5.2 | 0.08 (n/a) | 1.94% | 92 |

Against the model's assumptions (`SimSkill` accuracy and head rate, after #766): the Rookie lands 49 to 60% of its shots
and 62 to 68% of the hits are the head (weak: 0.45 and 0.68); the Regular 74 to 76% and 72 to 76% (average: 0.65 and
0.81); the Veteran 81 to 84% and 73 to 83% (strong: 0.82 and 0.85). Kills a bot-minute are 4 to 6 (Rookie), 7 to 10
(Regular) and 7 to 10 (Veteran): they fall with the team size because the dead are shared. A revive succeeds in 84 to
100% of tries (the tries are few for the Regular and Veteran: nobody is down much). The Rookie spends 0.54 to 0.81 of
what it earns against the model's 0.70 to 0.73 and the Regular 0.68 to 0.74 against 0.64 to 0.71: the shop gap of #228
(0.5 to 0.6 against 0.8 to 0.87) is closed, and the spend gate carried from #228 (points spent over earned within 20% of
the simulator's) holds for the Regular in all three team sizes and for the Rookie in the team of one and two (not four:
0.54 against 0.72); the split by category is in `report.json` of each run. `SimSkill` is not changed.

**Gates** (a person stand-in and three Regular bots for the last three rows, Follow and Hold given by the person at the
start):

| Cell | Nights | Nights that broke a gate | Which |
| --- | ---: | ---: | --- |
| rookie_1 | 8 | 0 | none |
| rookie_2 | 8 | 0 | none |
| rookie_4 | 8 | 0 | none |
| regular_1 | 8 | 0 | none |
| regular_2 | 8 | 1 | idle under Roam over 8 s x1 |
| regular_4 | 8 | 0 | none |
| veteran_1 | 8 | 0 | none |
| veteran_2 | 8 | 0 | none |
| veteran_4 | 8 | 0 | none |
| regular_3_roam_person | 8 | 1 | a round that would not end x1 |
| regular_3_follow_person | 8 | 2 | a round that would not end x2, idle with a zombie in view over 5 s x1 |
| regular_3_hold_person | 8 | 7 | off the Hold spot x7 |

The nine parity cells hold the hard gates in 71 of 72 nights; the one is a Regular idle for over 8 s under Roam. No
engine `ERROR` in any of the 96 nights, no stuck episode over 10 s, no rejected-buy loop, stuck share under 0.16% of
walking time in every cell without a person. The cells with a person do not hold all their gates: Hold keeps the spot
for 86 to 96% of the time under the stance (median 92%, 10 of 24 bots under the 92% gate; the causes and the fix are
[Hold and a boss](#hold-and-a-boss-769), #769) and Follow and Roam with a person left, in three nights of
sixteen, a round that did not end (a boss alive in round 14 or 15) and once a bot idle beside a zombie
([#770](https://github.com/Ryubara/deadnight/issues/770)).

**Think cost.** `test_bot_server_cost` fails on `main` too (mean 1020 microseconds, 6.1% of the tick, budget 5%), and
the soak's think p50 is 260 microseconds a bot and its p99 1.7 to 2.1 ms (worst 2.8 ms) on a busy machine:
[#771](https://github.com/Ryubara/deadnight/issues/771).

#### Idle bots and stalled rounds with a person (#770)

The first nightly soak left the Follow and Roam cells with a person (a stand-in, three Regular bots) breaking gates in
3 nights of 16: a round that went on for eight minutes, and bots idle with a zombie in view. **A night is not repeatable
by its seed**: the navigation bake finishes on a physics frame, so the same seed ran to the cap, or stalled, on
different runs. The causes were read from the nights that broke, with three additions to the soak:
`--tail=SECONDS` prints, every `--every` ticks of a round that has gone on that long, where every zombie is, its mode,
target and path length, and what each player holds and does; `--watch=2,3,4` takes several seats; and the report carries
samples of a bot far from the person (`far_samples`), the idle samples say whether the zombie was left to a person
(`left_to_a_person`), the roam samples where the path ended (`path_end`, `stopped_short`), and `relocated` counts the dead
put back on a spawn point. The evidence of the 24 baseline nights is in the scratch folder of the task.

| Failure | Cause | Fix | Test |
| --- | --- | --- | --- |
| Idle 6 to 12 s, a loaded gun, a zombie in sight at 6 to 12 m, `note hold`, `target_id -1` (every sample of Follow) | Kill courtesy: a zombie a person aims at is theirs, and the stand-in (a dry pistol) kept its aim on a zombie it did not kill | A zombie is the bot's too after `BotCombat.COURTESY_SECONDS` (3 s) of being left to a person, counted for each zombie; looking away for a moment does not give it back | `test_bot_combat.gd`: `test_a_zombie_left_to_a_person_is_the_bots_after_a_few_seconds`, `test_courtesy_counts_each_zombie_on_its_own...` |
| Idle beside a crawler that swings from 1.4 m with a dry gun, `note fight` | The quick melee struck inside 1.4 m (`QUICK_REACH_MARGIN` 0.2 inside a reach of 1.6); the dead swing from 1.4 m: a zombie at its own reach was never hit back | The margin is 0 (the blow reaches 1.6 and the sweep has a radius of 0.4) | `test_bot_motor.gd`: `test_the_quick_melee_reaches_a_zombie_standing_where_it_swings_from` |
| Roam: a bot standing 92 s (and 13 s) with `note roam`, path OK, the goal 2 m away | The walking mesh ends up to 2.5 m short of a place (`BotPath.REACHED_SHORT`); the legs stood at the end of the path, within the goal's radius of it, and sent no motion; the stuck ladder only judges a bot commanded to walk, and `BotRoam` kept the place until the bot was within 1.5 m | `BotLegs.stopped_short_of` says it; `BotRoam.plan` takes the place as reached | `test_bot_legs.gd`, `test_bot_roam.gd` |
| A round of eight minutes with one walker alive (Follow; three of three) | The walker stood in a pocket of the walking mesh: `map_get_path` from there is two points, ending at the pocket's edge; nothing a bot does reaches it ([Dead stranded in a pocket](zombies.md#dead-stranded-in-a-pocket-of-the-mesh-770)) | `ZombieSim` says a zombie 12 m or more from its target with a path that stops 3 m or more short of it is stranded after 12 s; `ZombieDirector` puts it back on a spawn point | `test_zombie_strand.gd`, and in the real lot `test_zombie_stranded.gd` |
| A round of eight minutes with two headliners kiting the person stand-in (Roam) | A person sees the last three zombies outlined through the walls (`ZombieMarks`) and goes to them; the bots roamed 40 to 100 m away and never saw the boss | `BotHunt` (below) | `test_bot_hunt.gd` |

**`BotHunt`.** `BotClient` tells the brain the marked zombies the way the screen does (`BotBeliefs.last_dead`: the
phase is a round, `remaining` is one to `ZombieTuning.mark_last`, the zombies that are not dying; the one place the
filter of `BotPerception` lets positions of unseen dead through, because the outline does for a person). Once the
round has been down to them for 15 s, a bot that is free (nothing believed within 12 m, no target, rounds in a gun,
not Safe, not under Hold) and that holds the claim by distance (`BotClaims`, `BotTeam.hunts`: the nearest free bot)
walks to within 6 m of the nearest of them (`note hunt`, counted as an errand by the far-from-the-person gate); under
Follow only to one 30 m or more from the person. It gives a zombie up for 30 s when the mesh has no way to it or when
it stands within 7 m of it for 6 s and does not see it.

**Measured** (`--profile=regular --bots=3 --person`, Follow and Roam, round cap 16, machine shared with other work; the
before is 32 nights on the code of `main` at 1a4e3016 with only the tracing added, the after 23 nights on this change; a
night is not repeatable by seed, so the two sets are different nights):

| | Before (32 nights) | After (23 nights) |
| --- | ---: | ---: |
| Nights that broke a gate | 11 | **3** |
| A round that would not end | 3 | 1 |
| A bot idle with a zombie in view over 5 s | 2 | **0** |
| A bot idle under Roam over 8 s | 3 (92 s, 15.5 s, 13.4 s) | **0** |
| A bot beyond 25 m of the person for over 20 s (Follow) | 4 | 2 |

**Not fixed, left as an issue.** The Follow gate "beyond 25 m of the person for over 20 s" still breaks in 2 nights of
12: one bot at 32 to 60 m, running at 7 m/s with the note `follow` or `retreat`, not stuck, the person a stand-in that
walks about. The samples are in the report (`far_samples`); the cause is not found. One night in 23 still ended with a
round of eight minutes: round 15 under Follow, two headliners alive, the person and two bots down and the last bot
with rifle and shotgun dry (`rifle [0, 0, 1]`, buying rounds for 30 s at a time under `ammo_urgent`), a lost night
rather than a lost zombie. Kills, hits and round reached are not compared: 23 nights do not rank a tuning.

#### A Follow bot far from the person (#784)

The one Follow gate #770 left, "a bot beyond 25 m of the person for over 20 s outside an errand", broke in about one night
in ten. `--watch=far` (a line a second for every bot up and 20 m or more from a person up: its note, where the person
is, the way it walks, the dead within 12 m and the nearest) found it: the runs are a bot with **six to twenty-four dead
within 12 m of it** (the nearest 0.4 to 6 m), the notes `retreat` and `fight` in turn, at 7 m/s, 30 to 90 m from the person,
in the late rounds (15 and up, the big packs). The catch-up after a far errand (`boards` 60 m away, then `follow` at
7 m/s for 7 to 9 s) is inside the gate's 20 s, and the many far lines of a night where the stand-in is down are not the
gate's (it counts persons on their feet): read the lines the gate would count, not the far ones.

**Cause.** A retreat picks one of twelve headings (`BotSteering`). The rating adds up the push of each of the eight
nearest dead; the pull toward the person was one flat `HOME_BEND` (0.9). With a pack on the bot's heels the sum is ten to
thirty, so the pull decided nothing and the flight ran straight away from the pack, the way away from the person
whenever the pack stood between. A probe of the steering (a hall, a pack of 2, 4 and 8 on the person's side, 3 to 4 m off):
a flat pull of 8 turns the flight for 2 dead and not for 4 or 8; the pull must grow with the number of dead.

**Fix.** `BotFightBrain.far_bend(distance, felt)`: under the order Follow the retreat's pull is `HOME_BEND` up to 16 m
from the person and grows to `FAR_BEND` (4) for each dead felt (the steering looks at eight at most, so 32) at 36 m. The
steering's own rule stays the guard: a heading that closes on the dead is never taken, so the pull only turns the flight
round the pack (a pack straight between the bot and the person is circled, not run into), and the pack is led to the
person. Hold and Roam keep `HOME_BEND`. Test: `test_bot_steering.gd` sends eight dead between the bot and a person 30 m
off: the near pull runs straight away, the far one goes round (it failed first with a flat pull of 8).

**Measured** (`--profile=regular --bots=3 --order=follow --person`, round cap 30, machine shared, ten nights of seeds 600
to 604 and 700 to 704 each; the before is a detached checkout of this branch without the fix, with the same tracing; a
night is not repeatable by seed, so these are different nights):

| | Before (10 nights) | After (11 nights) |
| --- | ---: | ---: |
| Nights with a bot beyond 25 m of the person for over 20 s | 1 (23.9 s) | **0** |
| Longest such run in a night, median (s) | 13.1 | **5.9** |
| Seconds a bot is beyond 25 m of a person up outside an errand, per night | 158 | **81** |
| Round reached, median | 16 | 16 |

The far seconds that are left include the walk back after an errand (`boards`, `buy` and `fuel` are left out of the
count while the errand lasts; the walk home is not). The round that would not end (two headliners, the last bot dry) is
the lost night that #770 describes and is untouched.

#### What is left, and how the three nights are read

- **Three consecutive nightly runs.** The workflow is new; its hard gates (every row of the gates table except parity)
  fail the run, and parity turns on with `--gate-parity` when #767 and #768 are done. The run history is where three in
  a row are read ([#772](https://github.com/Ryubara/deadnight/issues/772)). The first runs will fail on the cells with a
  person until #769 and #770 are fixed, which is the soak doing its job.
- **A bot-filled night against a human one.** Not measurable until there is telemetry of people; until then "neither
  easier nor harder than a human one" is the simulator's own levels, read as above: the Veteran is the strong level, the
  Regular is the average level made easier, the Rookie is the weak level made two to five rounds easier in a team. The
  rules' player scaling is **not retuned**: nothing measured says a bot weighted below one would bring a team nearer the
  model, and no night of people exists to say it from ([#772](https://github.com/Ryubara/deadnight/issues/772)).
- **The cap.** The report above is at round 16 because the nights past it cost 5 to 8 s of wall time a game minute; 7 or
  8 of the 8 Veteran nights reach it. The nightly run uses 20.
- **A soak is a sample of nights**: eight a cell is enough to see a gate break and not enough to rank two tunings that
  are a round apart (the median of four Regular bots moved between 10 and 12 between runs of 12 and of 4 nights). The
  nightly run's 100 nights are for that.

## Decisions of the maintainer

The seven open questions of the first draft were answered on 2026-11-02: **all seven recommendations accepted**.
They are decisions now, not options; the phases build to them.

| # | Question | Decision | What it means in the build |
| --- | --- | --- | --- |
| 1 | Teleport as a last resort? | **No teleporting bots.** | The stuck ladder ends in a report (`bot_stuck`) and a walk back along the breadcrumb trail, never a jump to the humans. A bot that cannot reach anyone fights where it stands. |
| 2 | Label bots? | **Yes, bots are labelled as bots.** | A mark in the lobby, the roster, the HUD's player box and the feed (`BOT` after the name); never in the command, which stays identical to a person's. The name comes from the profile's cast (Phase 6, built: `BotRoster`). |
| 3 | Do bots earn account progression? | **Bots earn points in the night, not XP.** | In-night points work as for a person (a bot buys doors with what it kills for). Account XP, rescue pay and mastery are never paid to a bot, and a night with bots is marked in the stats. The progression code reads `player_revived.reviver_id` and `player_added.bot` to skip bots; a bot that revives a human farms nothing. |
| 4 | Player scaling | **Bots count for zombie scaling.** | The boss health, the alive cap and the spawn rate scale with the number of seated players, bots included (a bot is a player to the rules: `add_player`). Phase 7 may weight a bot below one; the default is one. |
| 5 | Can people give bots orders? | **Orders by pings only.** *Superseded 2026-11-02 (#641): pings stay, and a command wheel adds three standing orders.* | The five pings of Phase 0 (`PingBoard.KINDS`: here, door, ammo, enemy, downed) pull a bot whatever its order. The standing orders are **Follow**, **Roam** and **Hold** ([Orders](#orders-follow-roam-and-hold-641)); there is still no text. |
| 6 | Voice | **No bot voice for now.** | Callouts are `bot_say` lines in the feed only; no audio assets are made for them until the maintainer asks. |
| 7 | A human takes a bot's slot | **A joining human inherits the bot's slot.** | The human gets the bot's seat, body, points, weapons, ammunition, grenades and health as they stand, and the bot is removed in the same tick. No reason to leave and rejoin. A human who leaves leaves the slot to a bot again, as it stands (Phase 6, built: `NightBots.adopt`). |

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

## Tuning the follow soak (#564)

*These numbers are the Follow order's: the soak gives it explicitly (`--order=follow`) since the default became Roam
([Orders](#orders-follow-roam-and-hold-641)). The within-12 m gate belongs to Follow alone.*

Measured with the move soak (`game/tests/captures/bots_move_soak.tscn`, `--tough=3`, 20 minutes, seeds 1 to 6,
four bots):

| Change | Stuck (share of walking time) | Within 12 m of the person |
| --- | --- | --- |
| Baseline | 1.62% | 0.85 to 0.93 |
| Navmesh contour error 1.3 to 1.0 cells | 1.30% (the locker at (3, -31) stopped being a cause) | about 0.91 |
| Also: a bot gives way to any bot standing still | 1.2% on five seeds, but a bot wedged for 61% of one seed | not better |
| Also: calm follow band 4-10 m to 4-8 m | 1.35% | about 0.91 (varies from 0.77 to 0.96 by seed) |

The default contour error of 1.3 cells cuts a corner by about 0.33 m at a 0.25 m cell, which puts the mesh edge
inside the bodies' margin: bots walked into locker and prop corners. The last two rows were tried and not kept. A
run's rounds differ by seed once the bots behave differently, so a few tenths of a percent between runs is noise;
compare over all six seeds. Remaining stuck episodes are bot against bot (44 of 98) and no contact (42).

The bands test reads the Veteran's dodge from a few dozen blows: on `main` four seeds read 0.50 (34 blows due) and ten
seeds read 0.67 (63), and with the tighter contour four seeds read 0.68 (19) and ten read 0.60 (45). The same fight is
bit-identical from run to run, so the four-seed number is a draw, not noise to average. The Veteran's true dodge sits
near the top of the band.

The same holds for every number of the test: any change to when the guns fire or where the zombies walk draws the seeds
again. The CI runner is deterministic for one build (`main` read the Veteran's head share at 0.26 over eight seeds in
every run), but a change draws different fights there and on a developer's machine alike. Carrying the tick's leftover
in the weapons' cooldown (#708; the pistol went from a shot every 17 ticks to 16.8 on average) read the head share at
0.22 on the runner over eight and over sixteen seeds (band 0.23 to 0.37), where sixteen seeds on a Windows machine read
0.30 before and 0.28 after, dodge 0.60 and 0.61, hit rate 0.88 and 0.86, and the Regular's dodge 0.15 and 0.14. The
runner's Veteran head share sits near the band's floor on any build, so the cure is the recalibration of the head
share to the hit zones (#694), not more seeds.

### Within 12 m counts only the bots that are up

A bot that is downed or dead cannot follow, and the soak counted its time as far: on seed 3 of `main`, 35 000 of about
290 000 samples. The soak now also prints `down_ticks` and `within_12m_up` (the share of the samples of bots that were
up). Six seeds, `--tough=3`, 20 minutes:

| | within 12 m, all samples | within 12 m, bots up |
| --- | --- | --- |
| `main` before the new contour | 0.83 to 0.93 | 0.90 to 0.93 (mean 0.92) |
| the new contour | 0.86 to 0.93 | 0.915 to 0.93 (mean 0.92) |

Of the time a bot that is up is far, 83 to 87% is the follow state, running (a bot that is far runs unless a dead one is
within 4 m) at about the speed of the person's own run: the person's sprint, a shop trip or a door outpaces the bots,
and they catch up when it stops. Bots standing still while far (waiting for a path query, or a door) are about 5% of
that time. Stuck seconds differ by half a point between two runs of one seed on a busy machine (the cause is not
found; the runs are not bit-identical under load), so compare a change over all six seeds and several runs, not one.

### The goals of #564 after the roam design

Bots roam by default and come to a person for a revive or a ping; Follow, Roam and Hold become player orders (issues
641 and 642). The goals of #564 are now:

- Stuck seconds under 1% of walking time on seeds 1 to 6 (`--tough=3`).
- Think p99 under 0.5 ms in the soak on an idle machine, or the budget in [Server cost](#server-cost) changed with the
  measurement.
- Within 12 m of the nearest person at 95%: moves to #641, where it belongs to the Follow order (0.92 now, counted over
  the bots that are up).

### A bot walks round a bot that stands still: not shipped

The idea: of two bots the higher seat gives way, so a bot that meets a lower-seat bot standing still walks into it and
waits. The rule made a bot give way to any bot slower than 0.6 m/s. Six seeds, `--tough=3`, 20 minutes, on `main`
with the slot fix (#625):

| | stuck (share of walking time) | worst bot, by seed |
| --- | --- | --- |
| without the rule | 1.46% (1.09 to 1.74 by seed) | 1.5 to 3.0% |
| with the rule | 1.28% (0.89 to 1.61 by seed) | 1.2 to 3.6% |

The 0.18 point gap is inside the half point two runs of one seed differ by, so the rule is not shipped. (An earlier
trial wedged a bot in the fountain slot; the slot is closed now and the wedge did not come back.) The patch is kept in
the scratch folder of the task, not in the repository.

The two gates still open on #564 need a quiet machine to settle: stuck under 1% per seed needs several batches of each
setup to see a change smaller than the noise, and the think p99 read 1 to 14 ms in these runs because other agents
were running. Measure both with nothing else running.

## Forty-minute nights on the second map (#695)

`smallmap_bot_night.tscn` with `--minutes=40 --rounds=10 --trace --short --zombies`, ten seeds each of one and of four
bots. A night "ends" when the bots all fall or round 10 closes; a stall runs the whole 2,400 s.

| | one bot | four bots |
| --- | --- | --- |
| before (`main`) | 2 of 10 stalled (seeds 2, 9) | 3 of 10 stalled (seeds 5, 7, 9) |
| after, this change | 9 of 10 end (seed 2 stalled) | 8 of 10 end (seeds 7 and 9 stalled) |
| after, with #709 (stairs) merged on top, the stalled seeds rerun | seed 2 ends | seeds 7 and 9 end |

What a stall looked like in the trace, and what each cost:

- A bot whose `arms` read `[0, 0]` for the gun in hand and `[0, n]` for the other (or the axe in hand, the shotgun at
  `[0, 54]` and ten dead within 8 m): `BotArsenal` had no rule for it (see above). Fixed here.
- `ctc=1 vis=1 tg=0` with the dead at 0.3 to 0.6 m: contacts in their reaction delay erased at every look
  (`BotPerception.ARM_REACH`). Fixed here.
- One dead one at (7, 1.5) in chase mode against the side wall of the stair along the hall's north wall, the bots at a
  "choke" beside it, the ray from the zombie to the bot blocked by `StairASide`: the dead climbing the stair
  ([#681](https://github.com/Ryubara/deadnight/issues/681), #709). Not this change; it ends once #709 is in.

Read a stall from the beliefs (`ctc`, `vis`, `tg`, the contact's age) and the plan's inputs (`arms`, the weapon in hand,
the nearest dead one) before guessing a cause: the first guess here (a train that gives no gap) was wrong.

## Revive return soak (#673)

Two parts, measured differently.

**The scenarios** (`tests/bots/test_bot_revive_return.gd`, the bots' beliefs on a clock with walking bots, so a rule is
the only difference between two runs). A person lies by a pack of 14 (`UNSAFE`), two bots stand 45 m off, the pack
goes at a given second of the 45 s clock:

| Pack goes at | Raised at, rules off | Raised at, staging on |
| --- | --- | --- |
| 30 s | 42.3 s | 36.3 s |
| 32 s | never (bled out) | 38.3 s |
| 34 s | never | 40.3 s |
| 36 s | never | 42.3 s |
| 38 s | never | 44.3 s |
| 40 s | never | never |

Staging moves the last second a pack can go and still leave a body to raise from between 30 s and 32 s
to between 38 s and 40 s. A stuck claimant
(nearer the body, its position never changes; the bot behind it is not 2 m nearer, so it never steals): without the
stall rule the person is never raised, with it the bot behind takes the claim after 5 s and raises at 9.6 s.

**The soak** (`tests/captures/bots_revive_soak.tscn`, four mixed bots, a fall forced every 10 s, 12 minutes, seeds 1 to
48, off = `--no-stage --no-stall`): bodies that bled out with a bot still up, per 1000 forced falls, by cause read from
the `BLEED` lines (the cause scheme is in the pull request):

| Cause | Off (49 of 2193) | On (46 of 2348) |
| --- | --- | --- |
| All | 22.3 | 19.6 |
| The last bot up, risk not clear (not for this rule) | 8.2 | 6.0 |
| Claimant stuck on `GO` | 0.9 | 0.9 |
| Unsafe for 10 s or more, then `LATE` | 5.0 | 6.0 |
| `LATE` without a long unsafe spell | 7.3 | 4.7 |
| Other | 0.9 | 2.1 |

The soak does not show the gain the scenarios do: 49 and 46 bleed-outs are within what the seeds move between runs (the
untargeted rows move by as much). The bleed-outs that stay are mostly packs and bosses that keep the body to the end
(a staged bot 12 m away with under 4 s left is `LATE`), which no rule here can help. Staging costs no raises: raises per
forced fall 0.94 off, 1.01 on; the nights that ended early were 15 of 24 either way in the first 24 seeds.

## A breaker the bot walks away from (#706)

An area's breaker is wanted only while a person (the bot itself when none is up) is within a lamp's reach of the
area. The breaker's stand can lie outside that reach, so the walk to it ended the want: the bot turned to its shopping,
walked back in, wanted the breaker again, and flipped between `breaker <area>` and `buy <item>` at every plan (the ticket
plaza's perk machine showed it). `BotErrands` now keeps the breaker it set out to throw on (`_breaker_id`, for one
`ERRAND_LIMIT`) until the circuit is on; one it goes to throw off is not kept. Test:
`test_a_bot_with_a_purchase_in_a_dark_area_throws_the_breaker_then_buys` in
`tests/night/test_bot_errands.gd` (the lamps' reach is cut to 4 m on the shipped lot so the breaker stands outside the
area). A want that depends on where the bot stands needs a commitment for the walk it causes.

## Hold and a boss (#769)

The first nightly soak (#231) found the Hold cell (a person stand-in and three Regular bots) with 10 of 24 bots under the
gate's 92% and, in 3 nights, a holder that stood 5 to 8 s with the headliner at 6 to 8 m, a pistol with rounds, and no
shot and no step. The causes, found with the soak's own samples (`off_after`, `away_notes`, `trips` and the idle sample's
`target_id` and `left_to_a_person`, all in `SoakWatch`):

1. **The idle holder was kill courtesy.** The idle sample read `target_id -1` with the boss believed and in sight, 6.6
   to 8.3 m off, in all 3 of 3 samples of a boss (`left_to_a_person: true`). `BotCombat.courtesy_holds` leaves a
   zombie 6 m or more away to a person aiming at it, and the person aims at the boss for as long as it lives. A boss is
   no one's kill: `courtesy_holds` is false for it. Test: `test_a_boss_is_never_left_to_a_person`.
2. **A boss keep-off with no limit, and a walk back into it.** `BotProfile.boss_keep` (6 m) backs a bot off the headliner
   under every order. A holder that backed off ran up to 14 m from the spot, the boss followed it to the spot (it
   walks to where the bots are), and the holder walked back toward the boss as soon as it was 6 m away: 400 to 2600 ticks
   of `hold_order` off the spot per bot-night after a `retreat`. A holder now keeps off a boss only while it is within
   `hold_back` (4 m) of the spot, as a Safe one backs off, and a holder off its place does not walk to a place the boss
   stands at (`hold_back`, it fights from where it is) until the boss is not there. Tests in `test_bot_hold_boss.gd`
   (three of four fail on the code before).
3. **The gate counted the walk home from a trip.** The Hold gate is "within 3 m of the spot for 92% of the time the bot
   is under the stance, not on a trip for a revive, a ping, a dodge or an errand", but the watch took the note
   `hold_order` for the stance, and the walk home carries it. The watch now holds a trip from the first note that is not
   the stance until the bot is back within 3 m, and reports the share both ways (`stance_share`: the gate;
   `stance_share_all`: the walk home counted) with the time away (`away_seconds`, its notes, the three longest trips).

**Measured** (12 nights each, seeds 21 to 26 and 31 to 36 on two runs, `--profile=regular --bots=3 --person
--order=hold`, the baseline a detached checkout of `main` at 1a4e3016 with the same watch):

| | Before | After |
| --- | ---: | ---: |
| Nights that broke a gate | 5 of 12 | **0 of 12** |
| Bots idle over 5 s with a zombie in view | 4 of 36 (longest 6.2 s) | **0 of 36** (longest 3.8 s) |
| Stance share, trips excluded (the gate) | median 99.4%, 1 bot under 92% | median 99.4%, **none** under 92% |
| Stance share, the walk home counted | median 92.6%, 13 bots under 92% | median 94.5%, 9 under 92% |
| Round reached | median 9.5 (6 to 10) | median 10.5 (8 to 12) |
| Downs per bot-hour | 7.7 | 7.9 |
| Kills per bot-minute | 2.90 | 3.42 |

**Where the time off the spot goes** (seconds per bot-hour up, the 6 nights with the breakdown; about 18 to 20% of the
time is away either way, and it is mostly the order's own trips): rounds for the pistol 205 (a holder with a pistol and
1000 to 2000 points goes eight times a night; the shop is #768's), standing off a boss at the spot 162 (27 before: they
no longer run from it and no longer walk into it, and shoot it from 4 to 6 m while it lives), the walk home 137 (194
before), the stampede's choke 114 (the round's stance replaces the order's), retreating 56 (147 before), a revive 33.
A trip is a line of the report, not a gate: the choke of a stampede lasts a minute and a boss at the spot keeps the
holders off it as long as it lives. The shopping of a holder (it has the points and never buys a better gun) is not
changed here.

Not changed, and seen once: a dry holder (0 rounds, 0 in reserve, a walker 2.3 m off) idle for 6.2 s in one baseline night
(seed 25, none in the 12 after the change); the quick melee of a dry bot is `BotCombat.may_melee`'s and #770's.

## Shopping at the second map's machines (#811, #821)

The overlay's `bot_shopping` now ends, after the last link, the box and the guns, with the hearty tonic (the soda
fountain), the re-cut (the bench upstairs), the swift rescue and the quick load tonics (ground floor coolers). The three
dearest coolers (Third Holster, Double Shot, Reload Shock) are left to a person. The profiles' `saves_for` (re-cut,
hearty) applies to the list, which is why the machines come after every link: a bot saving for a tonic holds back
everything after it, and a held-back link would hold the whole team's stairs.

**Cause of the flaky solo night (#821): a pick with no memory.** The chooser took "the nearest seller" by flat metres at
each think. The second map sells the shotgun twice (side room, upstairs); from the stair landing the two are within a
metre of each other, so the goal flipped every two seconds and the bot paced the landing for the whole break
(40 s of walking at x 9 to 11 m, no purchase, and no tonic or re-cut either). The lot has one seller of each item, so it
never showed. Three changes, all in the shopping code:

- `BotEconomy` picks the stand of a weapon, the box, a tonic, the re-cut and a grenade rack with `nearest_by_walk`:
  the walk length when the bot has legs, else the flat metres plus `RISE_WEIGHT` (8 m) a metre of height, and the
  stand it is already walking to counts 6 m nearer (`HEADING_CREDIT`).
- `BotErrands` keeps that heading for every purchase (it kept it for rounds only).
- An arrival needs the bot within `ARRIVE_HEIGHT` (1.5 m) of the stand's height: a bot under the upstairs bench was
  flat-close, "arrived", found no prompt and gave the re-cut up.

Measured (`bots_soak.tscn --map=small_indoor`, Regular, seeds 1 to 5, headless; `main` at b96eab2a against this branch):

| | rounds reached | tonics + re-cuts bought | longest stuck |
| --- | --- | --- | --- |
| one bot, before | 8, 9, 9, 8, 8 | none | 0.0 s |
| one bot, after | 18, 9, 18, 18, 17 | tonics 5000 and re-cuts 1500 to 4500 points in 4 nights (seed 2 died at round 9 first) | 1.5 s |
| four bots, before | 9, 9, 14, 12, 11 | none | 5.1 s |
| four bots, after | 11, 13, 10, 15, 14 | tonics in 4 of 5 nights, re-cuts in 2 | 2.4 s |

A lone bot that buys the tonics lasts twice the rounds it did: the machines are what the economy's late points are for.
`test_smallmap_bot_night.gd` holds the solo night over seeds 1, 3, 4 and 7 (it flaked on a seed picked to pass).
