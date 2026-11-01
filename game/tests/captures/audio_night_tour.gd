extends Node
## Scripted capture of the night's own sounds in a real night: the ambient bed fading in, the dead
## tearing the boards off a breach (the last board going), the score in the break, a player putting
## the boards back, then a door, the till, a blow of the crowbar, and the player's hurt and downed
## voices, each as the event the server would send. Every sound comes from `NightSounds` hearing
## the night; nothing here plays one itself. Run with Movie Maker (`--write-movie out.png
## --fixed-fps 10`), which writes the mix to `out.wav` beside the frames. Each sound prints
## `SOUND <seconds into the movie> <id>`, which `tools/audio/analyze.py capture --expect` checks the
## mix against.

const BREACH := &"nw"
const FIELD_VIEW_FROM := Vector3(-51.5, 3.2, -40.0)
const FIELD_VIEW_AT := Vector3(-62.0, 1.3, -46.0)
const REPAIR_VIEW_FROM := Vector3(-55.0, 2.6, -42.0)
const GIVE_UP_FRAMES := 6000
## Movie Maker's frame rate (`--fixed-fps`), to turn a frame count into seconds.
const MOVIE_FPS := 10.0
const GAP := 1.6

var _night: Night
var _camera: Camera3D
var _label: Label
var _bed: Label
var _heard := ""


func _ready() -> void:
	Audio.seed_random(88)
	# Guarded so the same scene runs on a build without the night's sounds (the "before" capture).
	if Audio.has_signal(&"played"):
		Audio.connect(&"played", _on_played)
	_build_overlay()
	_night = Night.new()
	add_child(_night)
	await _night.start(Night.Mode.MANUAL)
	_camera = Camera3D.new()
	_camera.fov = 62.0
	add_child(_camera)
	_camera.make_current()
	_camera.look_at_from_position(FIELD_VIEW_FROM, FIELD_VIEW_AT)
	var only_here: Array[Vector3] = []
	var gates := _night.world.spawn_gates()
	for point: Vector3 in gates:
		if gates[point] == BREACH:
			only_here.append(point)
	_night.server.director.spawn_points = only_here
	_say("The night begins: crickets, the highway and the score fade in")
	await _hold(300)
	_say("Round one: the dead come to the boards")
	_act(RulesAction.skip_break())
	await _until(func() -> bool: return _boards() < _whole())
	_say("A board is pulled off")
	await _until(func() -> bool: return _boards() == 0)
	_say("The last board goes")
	await _hold(120)
	_end_the_round()
	await _until(func() -> bool: return _night.state.phase() == GameRules.Phase.BREAK)
	_say("The break: the score comes back")
	_night.player().teleport(_night.world.repair_spot(BREACH))
	_camera.look_at_from_position(REPAIR_VIEW_FROM, FIELD_VIEW_AT + Vector3(0.0, 0.4, 0.0))
	await _hold(300)
	_say("A player hammers the boards back")
	var use := NightCommand.new()
	use.use = true
	use.motion.yaw = PI / 2.0
	await _until(
		func() -> bool:
			_night.link.send(use.to_dict())
			return _boards() >= _whole()
	)
	await _hold(180)
	await _extras()
	await _hold(240)
	print("voices started: ", Audio.started, "  culled: ", Audio.culled)
	# Loops still playing when the engine shuts down are reported as leaked resources: stop them and
	# let the mixer notice before quitting.
	Audio.stop_all()
	_night.queue_free()
	await _hold(3)
	get_tree().quit()


func _process(_delta: float) -> void:
	if not Audio.has_method(&"bed_fade_db"):
		_bed.text = "no ambient bed, no score, no board sounds"
		return
	_bed.text = (
		"crickets %.0f dB  highway %.0f dB  score %.0f dB  | last: %s"
		% [
			Audio.bed_fade_db(&"bed_crickets"),
			Audio.bed_fade_db(&"bed_highway"),
			Audio.bed_fade_db(&"bed_score"),
			_heard
		]
	)


## The sounds that need no fight: the events the server would send for them.
func _extras() -> void:
	_night.set_paused(true)
	var door: StringName = _night.world.door_ids()[0]
	var at_door := _night.world.door_points(door)[0]
	_say("A door is bought: the till rings at the player, then the door opens")
	_tell(
		{
			"type": &"purchase_made",
			"player_id": Night.PLAYER_ID,
			"item_id": door,
			"price": 750,
			"detail": {}
		}
	)
	await _hold(int(GAP * 60.0))
	_camera.look_at_from_position(at_door + Vector3(0.0, 2.0, 6.0), at_door)
	_tell({"type": &"door_opened", "door_id": door})
	await _hold(int(GAP * 2.0 * 60.0))
	_say("A crowbar swing and its blow")
	var muzzle := at_door + Vector3(0.0, 1.4, 0.0)
	_tell(
		{
			"type": &"shot_fired",
			"shooter_id": Night.PLAYER_ID,
			"weapon_id": &"crowbar",
			"seq": 1,
			"muzzle": muzzle,
			"ends": [muzzle],
			"ammo": 1,
			"reserve": 1
		}
	)
	await _hold(int(0.25 * 60.0))
	_tell(
		{
			"type": &"damage_dealt",
			"shooter_id": Night.PLAYER_ID,
			"target_id": 1,
			"zone": &"body",
			"damage": 40.0,
			"headshot": false,
			"melee": true,
			"pellets": 1,
			"health": 10.0,
			"point": muzzle + Vector3(0.0, 0.0, -1.0)
		}
	)
	await _hold(int(GAP * 60.0))
	_say("The player is hurt, twice, and goes down")
	for i in 2:
		_tell(
			{
				"type": &"player_hurt",
				"player_id": Night.PLAYER_ID,
				"damage": 20.0,
				"health": 60.0 - 20.0 * i,
				"max_health": 100.0,
				"bearing": 0.0,
				"source_id": 4
			}
		)
		await _hold(int(GAP * 60.0))
	_tell(
		{"type": &"player_downed", "player_id": Night.PLAYER_ID, "cause": &"blow", "bearing": 0.0}
	)
	await _hold(int(GAP * 2.0 * 60.0))


func _on_played(id: StringName, _position: Variant) -> void:
	_heard = String(id)
	print("SOUND %.2f %s" % [Engine.get_frames_drawn() / MOVIE_FPS, id])


func _boards() -> int:
	return _night.world.barricade(BREACH).boards()


func _whole() -> int:
	return _night.server.rules.tuning.barricades.boards


## Capture only: the dead are cleared and the round's plan emptied, so the break begins.
func _end_the_round() -> void:
	_night.server.rules._plan.clear()
	for zombie_id: int in _night.server.rules.zombie_ids():
		_act(RulesAction.zombie_gone(zombie_id))


func _act(action: Dictionary) -> void:
	_night.state.apply_events(_night.server.rules.apply(action))


func _tell(event: Dictionary) -> void:
	_night.state.apply_events([event])


func _say(text: String) -> void:
	_label.text = text
	print("STAGE %.2f %s" % [Engine.get_frames_drawn() / MOVIE_FPS, text])


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = _make_label(layer, 12.0, 20)
	_bed = _make_label(layer, 44.0, 14)


func _make_label(layer: CanvasLayer, top: float, size: int) -> Label:
	var label := Label.new()
	label.position = Vector2(16.0, top)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	layer.add_child(label)
	return label


func _hold(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame


func _until(done: Callable) -> void:
	for _i in GIVE_UP_FRAMES:
		if done.call():
			return
		await get_tree().physics_frame
	push_error("audio night tour: gave up waiting")
	get_tree().quit()
