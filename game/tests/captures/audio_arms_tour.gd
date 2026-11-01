extends Node
## Scripted capture of the weapons' and the lot's sounds in a real night, played from the
## player's own shoulder camera: a buy sequence (a refusal, a door, a wall weapon, ammunition, a
## tonic, fuel, the crane), a fight with every weapon (the dead walk at the player from a breach;
## each weapon fires, is reloaded by hand, is swapped, runs dry), a grenade, and the generator
## running low, dry and refuelled. Every sound comes from the night's own listeners
## (`WeaponSounds`, `GrenadeSounds`, `WorldSounds`); nothing here plays one. Run with Movie Maker
## (`--write-movie out.png --fixed-fps 30`), which writes the mix to `out.wav`. Each sound prints
## `SOUND <seconds into the movie> <id>` and each reload `RELOAD <seconds> <weapon>`, which
## `tools/audio/analyze.py capture --expect` and the reload check read.

const BREACH := &"nw"
const MOVIE_FPS := 30.0
const GIVE_UP_FRAMES := 6000
const WEAPONS: Array[StringName] = [&"pistol", &"smg", &"shotgun", &"rifle", &"flare_gun"]
## Seconds of shooting for each weapon.
const FIGHT_SECONDS := 2.0
## Metres: the dead this near are shot at.
const FIGHT_RANGE := 18.0

var _night: Night
var _label: Label
var _frame_start := 0


func _ready() -> void:
	# A small picture keeps the recording fast: the sound is what this capture is for.
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().size = Vector2i(480, 270)
	Audio.seed_random(77)
	Audio.played.connect(_on_played)
	_build_overlay()
	_night = Night.new()
	add_child(_night)
	await _night.start(Night.Mode.MANUAL, Night.SEED, _tuning())
	_night.player().camera_rig.camera().make_current()
	_night.state.event_received.connect(_on_event)
	_frame_start = Engine.get_frames_drawn()
	var gates := _night.world.spawn_gates()
	var only_here: Array[Vector3] = []
	for point: Vector3 in gates:
		if gates[point] == BREACH:
			only_here.append(point)
	_night.server.director.spawn_points = only_here
	await _buy_sequence()
	await _fight()
	await _grenade()
	await _generator()
	print("voices started: ", Audio.started, "  culled: ", Audio.culled)
	Audio.stop_all()
	_night.queue_free()
	await _hold(3)
	get_tree().quit()


## The shipped table with the dead coming quickly, so a short recording meets them.
func _tuning() -> RulesTuning:
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.rounds.speed_base = 2.2
	tuning.rounds.first_spawn_delay = 0.5
	tuning.rounds.intro_seconds = 3.0
	return tuning


func _buy_sequence() -> void:
	var rules := _night.server.rules
	_night.player().teleport(
		_night.world.door_points(&"door_concession")[0] + Vector3(2.0, 0.0, 2.0)
	)
	_say("Buying: too poor for a door, the buzzer")
	_act(RulesAction.buy(Night.PLAYER_ID, &"door_concession"))
	await _hold(40)
	_act(RulesAction.grant_points(Night.PLAYER_ID, 20000, &"grant"))
	await _hold(30)
	for step: Array in [
		["A door: unlock, then the till", &"door_concession"],
		["A wall weapon", &"weapon_shotgun"],
		["Rifle ammunition", &"ammo_rifle"],
		["A tonic", &"tonic_second_wind"],
		["The crane", &"crane_play"],
	]:
		_say(step[0])
		_act(RulesAction.buy(Night.PLAYER_ID, step[1]))
		await _hold(int(60.0 * 1.2))
	rules.generator.fuel = 60.0
	_say("Fuel")
	_act(RulesAction.buy(Night.PLAYER_ID, &"fuel_can"))
	await _hold(int(60.0 * 1.8))


func _fight() -> void:
	_night.player().teleport(_night.world.repair_spot(BREACH))
	_say("Round one: the dead come")
	_act(RulesAction.skip_break())
	await _until(func() -> bool: return _nearest() < FIGHT_RANGE)
	var carried := _night.server.combat.carried(Night.PLAYER_ID)
	for weapon in [&"smg", &"rifle", &"flare_gun"]:
		if not carried.has(weapon):
			_night.server._combat(CombatAction.give_weapon(Night.PLAYER_ID, weapon))
	for weapon in WEAPONS:
		_say("Fighting with the %s" % weapon)
		_night.server._combat(CombatAction.equip(Night.PLAYER_ID, weapon))
		await _hold(30)
		var shooting := int(FIGHT_SECONDS * 60.0)
		for tick in shooting:
			_send(_shoot_command(tick))
			if tick == shooting / 2:
				_send(_one_shot_command(true, false))
			await get_tree().physics_frame
		# The reload started mid-way sounds on the clip's frames while the trigger is still held.
		await _hold(90)
	_say("Swapping weapons")
	for _i in 4:
		_send(_one_shot_command(false, true))
		await _hold(40)


## A command that aims at the nearest zombie, or straight ahead when there is none, firing.
func _shoot_command(_tick: int) -> NightCommand:
	var command := NightCommand.new()
	var eye := _night.state.position() + Vector3(0.0, Autopilot.EYE, 0.0)
	command.origin = eye
	var target := Vector3.ZERO
	var best := INF
	for zombie in _night.state.zombies:
		var d: float = eye.distance_to(zombie["position"])
		if d < best and zombie["mode"] != ZombieBody.Mode.DYING:
			best = d
			target = zombie["position"]
	command.dir = (
		(target + Vector3(0.0, Autopilot.CHEST, 0.0) - eye).normalized()
		if best < INF
		else Vector3(-0.7, 0.0, -0.7)
	)
	command.fire = true
	command.muzzle = eye + command.dir * 0.8
	_aim_rig(command)
	return command


func _nearest() -> float:
	var eye := _night.state.position()
	var best := INF
	for zombie in _night.state.zombies:
		if zombie["mode"] != ZombieBody.Mode.DYING and zombie["mode"] != ZombieBody.Mode.EMERGING:
			best = minf(best, eye.distance_to(zombie["position"]))
	return best


func _one_shot_command(reload: bool, swap: bool) -> NightCommand:
	var command := NightCommand.new()
	command.reload = reload
	command.swap = swap
	command.origin = _night.state.position() + Vector3(0.0, Autopilot.EYE, 0.0)
	command.muzzle = command.origin
	return command


## The night does not run the grenade server yet (issue 239), so the events it would send are told
## to the client: a cook, a throw, two bounces and the blast.
func _grenade() -> void:
	_say("A grenade is cooked, thrown, bounces and bursts")
	var hand := _night.state.position() + Vector3(0.0, 1.4, 0.0)
	_tell({"type": &"cook_started", "player_id": Night.PLAYER_ID, "seq": 1, "fuse": 3.0})
	await _hold(int(60.0 * 1.8))
	var landing := hand + Vector3(-9.0, -1.2, -9.0)
	_tell(
		{
			"type": &"grenade_thrown",
			"grenade_id": 1,
			"thrower_id": Night.PLAYER_ID,
			"seq": 2,
			"position": hand,
			"velocity": Vector3(-9, 4, -9),
			"fuse_left": 1.2,
			"underarm": false,
			"cooked": true,
		}
	)
	await _hold(40)
	_tell(
		{"type": &"grenade_bounced", "grenade_id": 1, "point": landing, "speed": 9.0, "wall": false}
	)
	await _hold(25)
	_tell(
		{"type": &"grenade_bounced", "grenade_id": 1, "point": landing, "speed": 4.0, "wall": false}
	)
	await _hold(40)
	_tell(
		{
			"type": &"grenade_exploded",
			"grenade_id": 1,
			"thrower_id": Night.PLAYER_ID,
			"point": landing,
			"core_radius": 2.0,
			"radius": 6.0,
			"in_hand": false,
		}
	)
	await _hold(150)


func _tell(event: Dictionary) -> void:
	_night.state.apply_events([event])


func _generator() -> void:
	var generator := _night.server.rules.generator
	_say("The tank runs low: the engine coughs")
	_night.player().teleport(_night.world.switches.standing_point(&"booth"))
	await _hold(30)
	_act(RulesAction.set_circuit(&"booth", true))
	await _hold(40)
	_act(RulesAction.set_circuit(&"booth", false))
	await _hold(40)
	var engine := _night.world.greybox.get_node("GeneratorYard/Generator") as Node3D
	_night.player().teleport(engine.global_position + Vector3(0.0, 0.0, 4.0))
	await _hold(30)
	# The tank is set just above the low line and the rules tick it down across it, so the events
	# are the ones the rules send (a tick is an action; events raised outside one are dropped).
	generator.fuel = 25.2
	_act(RulesAction.tick(30.0))
	await _hold(240)
	generator.fuel = 8.0
	_act(RulesAction.tick(30.0))
	await _hold(240)
	_say("The tank runs dry: power down")
	generator.fuel = 0.3
	_act(RulesAction.tick(30.0))
	await _hold(300)
	_say("Fuel is bought: power up")
	_act(RulesAction.grant_points(Night.PLAYER_ID, 5000, &"grant"))
	_act(RulesAction.buy(Night.PLAYER_ID, &"fuel_can"))
	await _hold(300)


func _send(command: NightCommand) -> void:
	_night.link.send(command.to_dict())


func _aim_rig(command: NightCommand) -> void:
	var rig := _night.player().camera_rig
	rig.yaw = lerp_angle(rig.yaw, command.motion.yaw, 0.2)
	rig.pitch = lerpf(rig.pitch, asin(clampf(command.dir.y, -1.0, 1.0)), 0.2)


func _on_played(id: StringName, _position: Variant) -> void:
	print("SOUND %.3f %s" % [_seconds(), id])


func _on_event(event: Dictionary) -> void:
	if event["type"] == &"reload_started":
		print("RELOAD %.3f %s" % [_seconds(), event["weapon_id"]])


func _seconds() -> float:
	return (Engine.get_frames_drawn() - _frame_start) / MOVIE_FPS


func _act(action: Dictionary) -> void:
	_night.state.apply_events(_night.server.rules.apply(action))


func _say(text: String) -> void:
	_label.text = text
	print("STAGE %.3f %s" % [_seconds(), text])


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16.0, 12.0)
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)


func _until(done: Callable) -> void:
	for _i in GIVE_UP_FRAMES:
		if done.call():
			return
		await get_tree().physics_frame
	push_error("audio arms tour: gave up waiting")
	get_tree().quit()


func _hold(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame
