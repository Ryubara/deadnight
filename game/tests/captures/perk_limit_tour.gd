extends Node
## The perk limit match setting (#913) in the real night, from the player's shoulder camera: on
## Default the player carries four perks and the fifth machine says so; on Unlimited the same
## machine sells, the press buys the fifth perk and then the sixth, and the badges beside the health
## card grow to six. One PNG per stage into `--out=<folder>`, named `<--label=><stage>`; it prints
## what the card says. Run it through the no-focus launcher at the size to see:
## `gds godot -- --path game res://tests/captures/perk_limit_tour.tscn --resolution 1280x720 --
## --out=<folder> --label=after`.

const SETTLE_FRAMES := 20
const HOLD := 40
const SHOULDER_PITCH := 0.2

var _out := "user://perk_limit_tour"
var _label := "after"
var _night: Night
var _hud: Hud
var _yaw := 0.0
var _use := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--label="):
			_label = arg.trim_prefix("--label=")
	DirAccess.make_dir_recursive_absolute(_out)
	await _tour(false)
	await _tour(true)
	get_tree().quit()


func _tour(unlimited: bool) -> void:
	_hud = (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(_hud)
	add_child(layer)
	var tuning := (
		(load(GameRules.DEFAULT_TUNING_PATH) as RulesTuning).duplicate(true) as RulesTuning
	)
	tuning.rounds.first_spawn_delay = 6000.0
	_night = Night.new()
	_night.hud = _hud
	_night.match_settings = MatchSettings.new()
	if unlimited:
		_night.match_settings.perk_limit = MatchSettings.PERKS_UNLIMITED
	add_child(_night)
	await _night.start(Night.Mode.MANUAL, 7, tuning)
	_night.player().local_input = false
	_night.player().capture_mouse = false
	_night.ticked.connect(_send)
	var rules := _night.server.rules
	_night.state.apply_events(rules.apply(RulesAction.skip_break()))
	_night.state.apply_events(rules.apply(RulesAction.grant_points(1, 40000)))
	_night.player().camera_rig.camera().make_current()
	var ids := PerkEffects.tonic_ids(rules.tuning.economy)
	var limit := rules.tuning.economy.max_tonics
	var tag := "unlimited" if unlimited else "default"
	# The first four perks are bought as a player does: walk up to the machine and press use.
	for i in limit:
		await _stand_at(ids[i])
		await _press()
	await _stand_at(ids[limit])
	await _settle()
	await _shot("%s_1_fifth_machine" % tag)
	await _press()
	await _settle()
	await _shot("%s_2_after_the_press" % tag)
	if unlimited:
		await _stand_at(ids[limit + 1])
		await _press()
		await _settle()
		await _shot("%s_3_sixth_perk" % tag)
	print(
		(
			"TOUR %s perks held %d of %d, limit %d"
			% [
				tag,
				rules.players[1].tonics.size(),
				ids.size(),
				rules.settings.tonic_limit(rules.tuning.economy),
			]
		)
	)
	_night.queue_free()
	layer.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


## Stands the player a little to the side of the machine that sells `item`, facing it.
func _stand_at(item: StringName) -> void:
	var spot := Vector3.INF
	for candidate in _night.world.shop_spots():
		if candidate["shop_id"] == item:
			spot = candidate["position"]
	var machine := _machine_position(spot)
	var toward := machine - spot
	var flat := Vector3(toward.x, 0.0, toward.z).normalized()
	var side := Vector3(flat.z, 0.0, -flat.x) * 1.2
	_night.player().teleport(spot - flat * 0.9 + side + Vector3(0.0, 0.1, 0.0))
	_yaw = atan2(-flat.x, -flat.z)
	_night.player().camera_rig.yaw = _yaw
	_night.player().camera_rig.pitch = SHOULDER_PITCH
	_night.player().state.facing = _yaw
	_night.server.body_of(1).state.facing = _yaw
	await _hold(HOLD)


## The perk machine nearest the spot (the soda fountain is the sixth).
func _machine_position(spot: Vector3) -> Vector3:
	var best := spot
	var best_distance := INF
	for group in [PerkMachine.GROUP, SodaFountain.GROUP]:
		for node in get_tree().get_nodes_in_group(group):
			var distance := (node as Node3D).global_position.distance_to(spot)
			if distance < best_distance:
				best_distance = distance
				best = (node as Node3D).global_position
	return best


func _press() -> void:
	_use = true
	await _hold(2)
	_use = false
	await _hold(HOLD)


func _send() -> void:
	var command := NightCommand.new()
	command.motion.yaw = _yaw
	command.use = _use
	_night.link.send(command.to_dict())
	_night.player().camera_rig.yaw = _yaw


func _hold(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame


func _settle() -> void:
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame


func _shot(stage: String) -> void:
	await RenderingServer.frame_post_draw
	var prompt: Dictionary = _night.state.me().get("prompt", {})
	print("STAGE %s prompt %s perks %d" % [stage, prompt.get("kind", &""), _hud.state.perks.size()])
	get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [_out, _label, stage])
