extends Node
## The six perks, from the player's own camera, for captures and the browser (issue #687): each
## machine with its prompt card (name, price, what it does) and what a purchase looks like, then
## each effect as the real server runs it, with a label that says the measured number (shots in
## two seconds, seconds of a reload and of a revive, weapons carried, the shock shader on the dead).
## Not part of the game.
##
## `--group=machines|shock|fire|reload|third|revive|self` runs one group (the default is every
## group in turn, each in a night of its own); `--out=<folder>` saves a PNG at each shot on the
## desktop (a Movie Maker run needs none). In a browser `?group=` picks the group and the page
## publishes `window.__perks = {case, index}` at each shot for `tools/web_smoke/perks_capture.py`
## to screenshot, then `{done: true}`.
##
## Desktop: `gds godot -- --path game res://tests/captures/perks_sheet.tscn --resolution 1280x720 --
## --out=<folder>` (a window; the shots are the viewport's own pixels).

const SHOULDER_PITCH := 0.2
## Physics frames a shot is held (a browser frame takes several): long enough to screenshot.
const HOLD_WEB := 45
const HOLD := 12
const GROUPS: Array[StringName] = [
	&"machines", &"shock", &"fire", &"reload", &"third", &"revive", &"self"
]
const TICKS := 60

var _night: Night
var _hud: Hud
var _yaw := 0.0
var _pitch := SHOULDER_PITCH
var _command := NightCommand.new()
var _args := {}
var _web := OS.has_feature("web")
var _index := 0
var _label := Label.new()
var _events: Array[Dictionary] = []


func _ready() -> void:
	_read_args()
	var layer := CanvasLayer.new()
	_hud = (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	layer.add_child(_hud)
	_label.position = Vector2(560.0, 40.0)
	_label.add_theme_font_size_override(&"font_size", 34)
	_label.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.6))
	_label.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0))
	_label.add_theme_constant_override(&"outline_size", 10)
	layer.add_child(_label)
	add_child(layer)
	var wanted: Array[StringName] = GROUPS
	if _args.has("group"):
		wanted = [StringName(_args["group"])]
	for group in wanted:
		await _run_group(group)
	_say("window.__perks = {done: true};")
	if not _web:
		get_tree().quit()


func _read_args() -> void:
	for arg in OS.get_cmdline_user_args():
		_args[arg.trim_prefix("--").get_slice("=", 0)] = (
			arg.get_slice("=", 1) if "=" in arg else "1"
		)
	if _web:
		var query := str(JavaScriptBridge.eval("location.search"))
		for pair in query.trim_prefix("?").split("&"):
			if "=" in pair:
				_args[pair.get_slice("=", 0)] = pair.get_slice("=", 1)


## A fresh night for a group: the doors open (so every machine's area is a place), points to
## spend, the lamps on, the player's own camera current.
func _begin(tuning: RulesTuning = null) -> void:
	if _night != null:
		_night.queue_free()
		await get_tree().process_frame
	_night = Night.new()
	_night.hud = _hud
	add_child(_night)
	await _night.start(Night.Mode.MANUAL, 7, tuning)
	_night.player().local_input = false
	_night.player().capture_mouse = false
	_night.ticked.connect(_send)
	_night.state.event_received.connect(func(e: Dictionary) -> void: _events.append(e))
	var rules := _night.server.rules
	_night.state.apply_events(rules.apply(RulesAction.grant_points(1, 40000)))
	for door in [&"door_concession", &"door_booth", &"door_yard", &"door_back_lot", &"door_road"]:
		_night.state.apply_events(rules.apply(RulesAction.buy(1, door)))
	for circuit in [&"screen_lot", &"concession", &"booth", &"back_lot"]:
		rules.apply(RulesAction.set_circuit(circuit, true))
	_night.player().camera_rig.camera().make_current()
	await _hold(30)


func _run_group(group: StringName) -> void:
	_label.text = ""
	match group:
		&"machines":
			await _machines()
		&"shock":
			await _shock()
		&"fire":
			await _fire()
		&"reload":
			await _reload()
		&"third":
			await _third()
		&"revive":
			await _revive()
		&"self":
			await _self_revive()


# --- The machines ---


## Each machine, one after the other: walk up, the card with name, price and what it does; press
## use; the pour.
func _machines() -> void:
	await _begin()
	var rules := _night.server.rules
	for item_id in PerkEffects.tonic_ids(rules.tuning.economy):
		rules.players[1].tonics.clear()
		await _stand_at_perk(item_id)
		await _hold(70)
		await _shot("card_%s" % String(item_id).trim_prefix("tonic_"))
		_command.use = true
		await _hold(1)
		_command.use = false
		await _hold(34)
		await _shot("pour_%s" % String(item_id).trim_prefix("tonic_"))
		await _hold(60)


func _stand_at_perk(item_id: StringName) -> void:
	var spot := Vector3.INF
	for candidate in _night.world.shop_spots():
		if candidate["shop_id"] == item_id:
			spot = candidate["position"]
	var machine := _machine_of(item_id)
	var toward := machine - spot
	var flat := Vector3(toward.x, 0.0, toward.z).normalized()
	var side := Vector3(flat.z, 0.0, -flat.x) * 1.0
	_face(flat)
	_night.player().teleport(spot - flat * 1.0 + side + Vector3(0.0, 0.1, 0.0))
	_night.server.body_of(1).teleport(spot - flat * 1.0 + side + Vector3(0.0, 0.1, 0.0))
	await _hold(5)


func _machine_of(item_id: StringName) -> Vector3:
	for machine in get_tree().get_nodes_in_group(PerkMachine.GROUP):
		if (machine as PerkMachine).item_id() == item_id:
			return (machine as Node3D).global_position
	return (get_tree().get_nodes_in_group(SodaFountain.GROUP)[0] as Node3D).global_position


# --- The effects ---


func _shock() -> void:
	await _begin()
	_night.server.buy(1, &"tonic_reload_shock")
	var field := Vector3(0.0, 0.1, -20.0)
	_night.server.body_of(1).teleport(field)
	_night.player().teleport(field)
	_face(Vector3(0.0, 0.0, 1.0))
	_night.server.rules.apply(RulesAction.skip_break())
	await _hold(10)
	# Dead on every side, in reach and just out of it, close enough to be seen from the shoulder.
	await _wait_for_zombies(4)
	var ids: Array = _night.server.sim.zombies.keys()
	var spec := _night.server.rules.tuning.perks
	var ring := [0.45, 0.7, 0.55, 1.6]
	for i in mini(ids.size(), ring.size()):
		var angle := TAU * float(i) / float(ids.size()) + 0.6
		var zombie: ZombieBody = _night.server.sim.zombies[ids[i]]
		zombie.position = field + Vector3(cos(angle), 0.0, sin(angle)) * spec.shock_radius * ring[i]
	await _hold(6)
	_night.server.combat.weapon_of(1).ammo = 1
	_command.reload = true
	await _hold(2)
	_command.reload = false
	_label.text = "RELOAD SHOCK"
	# The camera looks down at the ground the shock runs over.
	_pitch = -0.5
	_night.player().camera_rig.pitch = _pitch
	await _hold(3)
	# The effect lives 0.7 s of the real clock, less than a slow browser frame needs to show it: it is
	# held at three moments of its life (the shader draws the same, only the clock is still).
	var moments: Array[float] = [0.12, 0.3, 0.55]
	for step in moments.size():
		for shock: ShockEffect in _night.find_children("*", "ShockEffect", true, false):
			shock.freeze(moments[step])
		await _shot("shock_%d" % step)
	for shock: ShockEffect in _night.find_children("*", "ShockEffect", true, false):
		shock.queue_free()
	await _hold(30)


func _wait_for_zombies(count: int) -> void:
	for _i in 2000:
		if _night.server.sim.zombies.size() >= count:
			return
		await get_tree().physics_frame


func _fire() -> void:
	await _begin()
	var field := Vector3(0.0, 0.1, -20.0)
	_night.server.body_of(1).teleport(field)
	_night.player().teleport(field)
	_face(Vector3(0.0, 0.0, 1.0))
	# The Tommy gun: a fast gun shows the perk best (the server shoots on whole 1/60 s ticks).
	_night.server.combat.apply(CombatAction.give_weapon(1, &"smg"))
	await _hold(10)
	var before := await _count_shots()
	_night.server.buy(1, &"tonic_double_shot")
	await _hold(5)
	var after := await _count_shots()
	_label.text = "SHOTS IN 2 S: %d  ->  WITH DOUBLE SHOT: %d" % [before, after]
	await _shot("fire_numbers")


## Holds the trigger for two seconds and counts the shots the server fires.
func _count_shots() -> int:
	_night.server.combat.weapon_of(1).ammo = 999
	_events.clear()
	var eye := _night.state.position() + Vector3(0.0, Autopilot.EYE, 0.0)
	_command.origin = eye
	_command.dir = NightServer.view_dir(_yaw, _pitch)
	_command.fire = true
	await _hold(2 * TICKS)
	_command.fire = false
	await _hold(2)
	return _events.filter(func(e: Dictionary) -> bool: return e["type"] == &"shot_fired").size()


func _reload() -> void:
	await _begin()
	var field := Vector3(0.0, 0.1, -20.0)
	_night.server.body_of(1).teleport(field)
	_night.player().teleport(field)
	_face(Vector3(0.0, 0.0, 1.0))
	await _hold(10)
	var plain := await _reload_seconds()
	_night.server.buy(1, &"tonic_quick_load")
	await _hold(5)
	var quick := await _reload_seconds()
	_label.text = "RELOAD: %.2f S  ->  WITH QUICK LOAD: %.2f S" % [plain, quick]
	await _shot("reload_numbers")


func _reload_seconds() -> float:
	_night.server.combat.weapon_of(1).ammo = 1
	_events.clear()
	_command.reload = true
	await _hold(2)
	_command.reload = false
	await _hold(TICKS * 3)
	var started := _events.filter(
		func(e: Dictionary) -> bool: return e["type"] == &"reload_started"
	)
	return float(started[0]["seconds"]) if not started.is_empty() else -1.0


func _third() -> void:
	await _begin()
	var field := Vector3(0.0, 0.1, -20.0)
	_night.server.body_of(1).teleport(field)
	_night.player().teleport(field)
	_face(Vector3(0.0, 0.0, 1.0))
	_night.server.buy(1, &"tonic_third_holster")
	_night.server.buy(1, &"weapon_shotgun")
	_night.server.buy(1, &"weapon_rifle")
	await _hold(20)
	for step in 3:
		_label.text = "WEAPONS CARRIED: %d" % _night.server.combat.carried(1).size()
		await _hold(25)
		await _shot("third_%d" % step)
		_command.swap = true
		await _hold(2)
		_command.swap = false


func _revive() -> void:
	await _begin()
	var tuning := _night.server.rules.tuning
	_night.server.apply({"type": NightServer.JOIN, "player_id": 2, "local": false})
	_night.server.rules.apply(RulesAction.skip_break())
	var field := Vector3(0.0, 0.1, -20.0)
	_night.server.body_of(1).teleport(field)
	_night.player().teleport(field)
	_night.server.body_of(2).teleport(field + Vector3(1.2, 0.0, -0.6))
	_face(Vector3(0.0, 0.0, 1.0))
	_night.server.buy(1, &"tonic_swift_rescue")
	await _hold(10)
	_night.state.apply_events(_night.server.rules.apply(RulesAction.blow(2, 500.0)))
	await _hold(20)
	_command.use_held = true
	var wanted := PerkEffects.revive_seconds(_night.server.rules, 1)
	_label.text = "REVIVE: %.2f S  (PLAIN: %.2f S)" % [wanted, tuning.health.revive_seconds]
	await _hold(int(wanted * TICKS * 0.55))
	await _shot("revive_half")
	await _hold(int(wanted * TICKS * 0.6))
	_command.use_held = false
	await _shot("revive_done")


func _self_revive() -> void:
	await _begin()
	_night.server.rules.apply(RulesAction.skip_break())
	var field := Vector3(0.0, 0.1, -20.0)
	_night.server.body_of(1).teleport(field)
	_night.player().teleport(field)
	_face(Vector3(0.0, 0.0, 1.0))
	_night.server.buy(1, &"tonic_swift_rescue")
	await _hold(10)
	_night.state.apply_events(_night.server.rules.apply(RulesAction.blow(1, 9999.0)))
	_label.text = "DOWN, ALONE: THE PERK GETS YOU UP"
	await _hold(40)
	await _shot("self_down")
	var seconds := _night.server.rules.tuning.perks.self_revive_seconds
	await _hold(int(seconds * TICKS))
	_label.text = (
		"UP AGAIN (USE %d OF %d)"
		% [
			_night.server.rules.players[1].self_revives,
			_night.server.rules.tuning.perks.self_revive_uses
		]
	)
	await _hold(30)
	await _shot("self_up")


# --- Plumbing ---


func _face(flat: Vector3) -> void:
	_yaw = atan2(-flat.x, -flat.z)
	_night.player().camera_rig.yaw = _yaw
	_night.player().camera_rig.pitch = _pitch
	_night.player().state.facing = _yaw
	_night.server.body_of(1).state.facing = _yaw


func _send() -> void:
	var command := NightCommand.new()
	command.motion.yaw = _yaw
	command.motion.pitch = _pitch
	command.use = _command.use
	command.use_held = _command.use_held
	command.reload = _command.reload
	command.swap = _command.swap
	command.fire = _command.fire
	command.origin = _command.origin
	command.dir = _command.dir
	_night.link.send(command.to_dict())
	_night.player().camera_rig.yaw = _yaw


func _hold(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame


## One shot: published for a browser probe, saved on the desktop, and held for a moment.
func _shot(name: String) -> void:
	_index += 1
	_say("window.__perks = {case: '%s', index: %d};" % [name, _index])
	if not _web:
		await RenderingServer.frame_post_draw
		var folder: String = _args.get("out", "")
		if folder != "":
			DirAccess.make_dir_recursive_absolute(folder)
			get_viewport().get_texture().get_image().save_png("%s/%s.png" % [folder, name])
	await _hold(HOLD_WEB if _web else HOLD)


func _say(script: String) -> void:
	if _web:
		JavaScriptBridge.eval(script)
