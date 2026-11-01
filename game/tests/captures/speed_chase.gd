extends Node
## A walker and a runner chase the player on lit ground or on ground with its circuit off, filmed
## through the player's own shoulder camera. Not part of the game. The player is the real one
## (`Night` in human mode, driven with the real input actions); only the two dead are put on the
## lot by hand, at the speeds the shipped tuning gives a round's walker and runner, so the same
## script films any build of the game (`docs/research/movement-speeds.md`, section 6).
##
##     godot --path game res://tests/captures/speed_chase.tscn --no-window \
##         --write-movie <abs>/chase.avi --fixed-fps 30 --quit-after 1200 -- --ground=dark
##
## Arguments after `--`: `--ground=lit|dark` (default lit), `--round=N` (default 8),
## `--label=TEXT` (the first line of the caption), `--flee=SECONDS` (how long the player runs
## away, default 4.5), `--sprint` (the player sprints away instead of running), `--probe` (print
## where the ground is lit and walkable, then quit), `--log` (print the measured speeds).
## Frames per second of the clip come from `--fixed-fps`; the night runs at 60 ticks either way.

const TICKS_PER_SECOND := 60.0
## Where the player stands, and the way the camera looks (the dead come from there). The lane is
## the field's long avenue, north to south: ground the lamps light for about 32 m (`--probe`), apart
## from one dark row at z -28, and open between the cars. The player backs away down it, so the
## camera keeps the dead in view.
const PLAYER_AT := Vector3(-4.0, 0.05, -38.0)
const LOOK_YAW_DEGREES := 0.0
## How far ahead the dead appear, and how far to the right of the player each stands (the shoulder
## camera keeps the player on the left of the picture, so the dead are on its right).
const START_AHEAD := 11.0
const START_WALKER_RIGHT := 2.8
const START_RUNNER_RIGHT := 1.0
## The player backs away when the nearest of the dead is this close.
const FLEE_WITHIN := 6.0
## Seconds of idle before the dead show, and the most the clip waits after the player stops for
## them to arrive (the old, slow dead take longest).
const LEAD_IN := 1.0
const TAIL_MAX := 16.0
## The dead are on the player when the nearest is this close; the clip ends this long after.
const ARRIVED_WITHIN := 1.6
const ARRIVED_HOLD := 1.5
## The two dead's ids: outside anything the rules would hand out.
const WALKER_ID := 9001
const RUNNER_ID := 9002
## Real seconds the audio mixer gets to drop stopped voices, and frames the program waits for a
## navigation bake, before it quits (the same care as `autopilot_night.gd`).
const QUIT_SETTLE_SECONDS := 0.3
const BAKE_WAIT_FRAMES := 600
## Seconds the measured speeds average over.
const MEASURE_WINDOW := 1.0
## A night this long never calls its first round (the capture puts the dead on the lot itself).
const NO_ROUND_SECONDS := 100000.0

var _args := {}
var _night: Night
var _player: Player
var _label: Label
var _ticks := 0
var _flee_tick := -1
var _stop_tick := -1
var _speeds: Dictionary[int, float] = {}
var _speed_marks: Dictionary[int, Vector3] = {}
var _player_speed := 0.0
var _player_mark := Vector3.ZERO
var _nominal := {}
var _dark := false
var _finishing := false
var _arrived_ticks := 0


func _ready() -> void:
	_args = _parse_args()
	_dark = String(_args.get("ground", "lit")) == "dark"
	var layer := CanvasLayer.new()
	add_child(layer)
	_night = Night.new()
	add_child(_night)
	await _night.start(Night.Mode.HUMAN, Night.SEED, _tuning())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_player = _night.player()
	_player.capture_mouse = false
	# A mouse that moves on this machine must not turn the camera: the controls still come from the
	# input actions the script presses (`Player.sample_command`), only the mouse look is off.
	_player.local_input = false
	if _dark:
		# The client hears it too (the lamps follow its events), as it would from the server.
		for circuit_id in _night.world.switches.circuit_ids():
			var events := _night.server.rules.apply(RulesAction.set_circuit(circuit_id, false))
			_night.state.apply_events(events)
	if _args.has("probe"):
		_probe()
		get_tree().quit()
		return
	_player.teleport(PLAYER_AT)
	_player.camera_rig.yaw = deg_to_rad(LOOK_YAW_DEGREES)
	_player.camera_rig.pitch = 0.0
	_make_caption(layer)
	_night.ticked.connect(_on_tick)


func _tuning() -> RulesTuning:
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.rounds.intro_seconds = NO_ROUND_SECONDS
	return tuning


## The walker's or the runner's speed in this round before jitter, as the rules' own tuning gives
## it: the round's walking speed times the type's multiplier, held at the cap.
func _speed_of(type_id: StringName) -> float:
	var tuning: RulesTuning = _night.server.rules.tuning
	var type := tuning.roster.type_of(type_id)
	var speed := tuning.rounds.speed_for_round(int(_args.get("round", 8))) * type.speed_multiplier
	return minf(speed, tuning.rounds.speed_cap)


func _spawn(id: int, type_id: StringName, offset: float) -> void:
	var sim := _night.server.sim
	var type := _night.server.rules.tuning.roster.type_of(type_id)
	var profile := ZombieProfile.from_type(type, type.looks[0], sim.tuning)
	var ahead := Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, deg_to_rad(LOOK_YAW_DEGREES))
	var apart := ahead.cross(Vector3.UP)
	var at := PLAYER_AT + ahead * START_AHEAD + apart * offset
	at.y = 0.0
	# Facing the player: yaw 0 looks along -z, as the sim's own yaw does.
	var yaw := atan2(-(PLAYER_AT.x - at.x), -(PLAYER_AT.z - at.z))
	sim.spawn(id, _speed_of(type_id), at, yaw, profile)
	_nominal[id] = _night.server.rules.tuning.rounds.speed_on_ground(_speed_of(type_id), not _dark)


func _make_caption(layer: CanvasLayer) -> void:
	_label = Label.new()
	_label.position = Vector2(460, 880)
	_label.size = Vector2(1000, 160)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 10)
	layer.add_child(_label)


func _on_tick() -> void:
	var now := _ticks / TICKS_PER_SECOND
	_ticks += 1
	if _ticks == roundi(LEAD_IN * TICKS_PER_SECOND):
		_spawn(WALKER_ID, &"walker", START_WALKER_RIGHT)
		_spawn(RUNNER_ID, &"runner", START_RUNNER_RIGHT)
		_mark_speeds()
	_measure(now)
	if _flee_tick < 0 and _nearest() <= FLEE_WITHIN and _ticks > LEAD_IN * TICKS_PER_SECOND:
		_flee_tick = _ticks
		Input.action_press(&"move_back")
		if _args.has("sprint"):
			Input.action_press(&"sprint")
	if _flee_tick >= 0 and _stop_tick < 0:
		if _ticks - _flee_tick >= roundi(float(_args.get("flee", 4.5)) * TICKS_PER_SECOND):
			_stop_tick = _ticks
			Input.action_release(&"move_back")
			Input.action_release(&"sprint")
	if _stop_tick >= 0:
		if _nearest() <= ARRIVED_WITHIN:
			_arrived_ticks += 1
		var waited := _ticks - _stop_tick
		if (
			_arrived_ticks >= roundi(ARRIVED_HOLD * TICKS_PER_SECOND)
			or waited >= roundi(TAIL_MAX * TICKS_PER_SECOND)
		):
			_finish()
	_caption()


func _finish() -> void:
	if _finishing:
		return
	_finishing = true
	_night.running = false
	for _i in BAKE_WAIT_FRAMES:
		if not _night.world.navigation.is_busy():
			break
		await get_tree().process_frame
	Audio.stop_all()
	await get_tree().create_timer(QUIT_SETTLE_SECONDS).timeout
	get_tree().quit()


## The distance from the player to the nearest of the two (a large number before they exist).
func _nearest() -> float:
	var best := INF
	for id in [WALKER_ID, RUNNER_ID]:
		var zombie: ZombieBody = _night.server.sim.zombies.get(id)
		if zombie != null:
			best = minf(best, _flat(zombie.position, _player.global_position))
	return best


func _mark_speeds() -> void:
	for id in [WALKER_ID, RUNNER_ID]:
		var zombie: ZombieBody = _night.server.sim.zombies.get(id)
		if zombie != null:
			_speed_marks[id] = zombie.position
	_player_mark = _player.global_position


## Speed over the last `MEASURE_WINDOW` seconds, from the positions themselves.
func _measure(now: float) -> void:
	if _ticks % roundi(MEASURE_WINDOW * TICKS_PER_SECOND) != 0:
		return
	for id in _speed_marks:
		var zombie: ZombieBody = _night.server.sim.zombies.get(id)
		if zombie == null:
			continue
		_speeds[id] = _flat(zombie.position, _speed_marks[id]) / MEASURE_WINDOW
		_speed_marks[id] = zombie.position
	_player_speed = _flat(_player.global_position, _player_mark) / MEASURE_WINDOW
	_player_mark = _player.global_position
	if _args.has("log"):
		print(
			(
				"MEASURE t=%.1f walker=%.2f runner=%.2f player=%.2f gap=%.1f yaw=%.1f pads=%d"
				% [
					now,
					_speeds.get(WALKER_ID, 0.0),
					_speeds.get(RUNNER_ID, 0.0),
					_player_speed,
					_nearest(),
					rad_to_deg(_player.camera_rig.yaw),
					Input.get_connected_joypads().size()
				]
			)
		)


func _caption() -> void:
	var lines: Array[String] = []
	var title := String(_args.get("label", ""))
	if title != "":
		lines.append(title)
	var round_number := int(_args.get("round", 8))
	lines.append(
		(
			"ROUND %d  -  %s"
			% [round_number, "DARK: the circuit is off" if _dark else "LIT: under the lamps"]
		)
	)
	if _nominal.has(WALKER_ID):
		lines.append(
			(
				"walker %.2f m/s    runner %.2f m/s    you %.1f m/s"
				% [_nominal[WALKER_ID], _nominal[RUNNER_ID], _player_speed]
			)
		)
		lines.append("nearest dead %.1f m behind" % _nearest())
	_label.text = "\n".join(lines)


## The ground the chase happens on, as the rules ask it, and where a body can stand: for finding
## a lane (`--probe`). L is lit, . is not, # is not walkable.
func _probe() -> void:
	var map := _night.world.map()
	for z in range(-50, -14, 1):
		var row := ""
		for x in range(-20, 21, 1):
			var at := Vector3(x, 0.0, z)
			var near := NavigationServer3D.map_get_closest_point(map, at)
			if Vector2(near.x - at.x, near.z - at.z).length() > 0.6:
				row += "#"
			else:
				row += "L" if _night.world.is_lit(at) else "."
		print("z=%4d %s" % [z, row])
	print("x from -20 to 20 step 1; player spawn %s" % _night.world.player_spawn(0))


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
