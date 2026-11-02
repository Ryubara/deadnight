class_name BotRig
extends RefCounted
## A bot with no server behind it, for the suites that test the bot's own parts: the zombies are
## entries the test moves by hand, the frame is built from them (zombies as the wire carries
## them), the sight is a callable the test sets, and a trigger pull becomes a `shot_fired` event
## after the weapon's interval, as the server would answer. A tick is one step of `Night.STEP`;
## nothing waits on the clock.

const STEP := Night.STEP
const ME := 1
## The weapon the rig's bot carries.
const WEAPON := &"pistol"

var bot: BotClient
var profile: BotProfile
var level: BotLevel
## Where the bot stands, and the body's facing the frame carries.
var position := Vector3.ZERO
var facing := 0.0
## Zombies by id: `ZombieBody`, moved by the test.
var zombies: Dictionary[int, ZombieBody] = {}
## Every action the bot sent, and the tick of each shot the rig let go.
var sent: Array[Dictionary] = []
var shot_ticks: Array[int] = []
var tick_count := 0
var round_number := 1
var health := 100.0
var downed := false
## Whether the rig answers a pulled trigger with a shot (turn off to watch the aim alone).
var shooting := true
## Whether the ground is lit everywhere.
var lit_ground := true

var _sight: Callable = Callable()
var _ammo := 8
var _cooldown := 0.0
var _rng_seed: int


func _init(
	p_profile: BotProfile = null,
	bot_seed: int = 1,
	sight: Callable = Callable(),
	lit: bool = true,
	p_rounds: RoundTuning = null
) -> void:
	profile = p_profile if p_profile != null else BotProfile.regular()
	_sight = sight
	_rng_seed = bot_seed
	lit_ground = lit
	# Callables to methods, not lambdas: a lambda that names a member holds the rig and the rig
	# holds the bot, a cycle that would still be alive when the engine exits.
	level = BotLevel.new(
		Callable(self, &"_distance_to_wall"),
		Callable(self, &"_is_lit"),
		p_rounds if p_rounds != null else RoundTuning.new()
	)
	var state := ClientState.new()
	state.player_id = ME
	bot = BotClient.new(state, profile, bot_seed, Callable(self, &"_record"), level)


func set_sight(sight: Callable) -> void:
	_sight = sight


## A zombie standing at `at`, walking (CHASE), with `id`.
func put_zombie(id: int, at: Vector3, mode := ZombieBody.Mode.CHASE) -> ZombieBody:
	var zombie := ZombieBody.new()
	zombie.id = id
	zombie.position = at
	zombie.mode = mode
	zombies[id] = zombie
	return zombie


## One tick: the server's side (the frame and the shot answered), then the bot's.
func step(extra_events: Array = []) -> NightCommand:
	tick_count += 1
	_cooldown = maxf(_cooldown - STEP, 0.0)
	var events: Array = [_frame()]
	events.append_array(extra_events)
	bot.hear(events)
	var command := bot.tick(STEP)
	if shooting and command.fire and _cooldown <= 0.0 and _ammo > 0:
		_cooldown = WeaponCatalog.get_def(WEAPON).fire_interval
		_ammo -= 1
		shot_ticks.append(tick_count)
		bot.hear([{"type": &"shot_fired", "shooter_id": ME, "weapon_id": WEAPON}])
		if _ammo == 0:
			_ammo = WeaponCatalog.get_def(WEAPON).magazine_size  # An instant reload.
	return command


func run(count: int) -> void:
	for _i in count:
		step()


func _frame() -> Dictionary:
	return {
		"type": &"frame",
		"tick": tick_count,
		"phase": GameRules.Phase.ACTIVE,
		"round": round_number,
		"zombies": ZombieCodec.encode(zombies),
		"players":
		{
			ME:
			{
				"pos": position,
				"facing": facing,
				"health": health,
				"downed": downed,
				"weapon": WEAPON,
				"ammo": _ammo,
				"reserve": 32,
				"reloading": false,
				"arms": {WEAPON: [_ammo, 32, 0]},
				"points": 0,
				"prompt": {},
			}
		},
	}


func _record(action: Dictionary) -> void:
	sent.append(action)


func _is_lit(_point: Vector3) -> bool:
	return lit_ground


func _distance_to_wall(from: Vector3, to: Vector3) -> float:
	return float(_sight.call(from, to)) if _sight.is_valid() else -1.0


## The view of the bot's last command, as a direction.
static func view_of(command: NightCommand) -> Vector3:
	return (
		Basis.from_euler(Vector3(command.motion.pitch, command.motion.yaw, 0.0)) * Vector3.FORWARD
	)
