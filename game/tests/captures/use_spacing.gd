extends Node
## The use prompt from the player's own camera at a window being boarded, with the wall weapon or
## locker beside it, for the before and after captures of #908: the player has both hands full,
## stands where a person mends the window (`NightWorld.repair_spot`) looking at it, every board
## torn off. One PNG a shot into the folder (`<name>.png`), and a `PROMPT` line with what the card
## offers. Not part of the game; run it windowed through the kit's private desktop:
##
##   gds godot -- --path game res://tests/captures/use_spacing.tscn -- --out=<folder>

const SMALL := "res://world/smallmap/smallmap_greybox.tscn"
## What is shot: map scene, breach id, a name for the file.
const SHOTS: Array[Array] = [
	[SMALL, &"upper_a2", "small_upper_a2"],
	[SMALL, &"start_1", "small_start_1"],
]
const SETTLE := 40

var _night: Night
var _out := "user://use_spacing"


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	await _build(SMALL)
	for shot in SHOTS:
		await _one(shot[1], shot[2])
	# The worst place: where a person mending `upper_a2` is offered a weapon that replaces the one in
	# hand (`--find`), or the place a `--find` run printed (`--at=x,y,z`, for the other build).
	var at := Vector3.INF
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--at="):
			var parts := argument.trim_prefix("--at=").split(",")
			at = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	if OS.get_cmdline_user_args().has("--find"):
		at = _find(&"upper_a2")
		print("FOUND ", at)
	if at.is_finite():
		await _one(&"upper_a2", "small_upper_a2_worst", at)
	get_tree().quit()


## A standing point in the breach's reach where the card offers a weapon that replaces the one in
## hand, looking at the window, or `Vector3.INF`.
func _find(breach: StringName) -> Vector3:
	var rules := _night.server.rules
	for _i in rules.tuning.barricades.boards:
		rules.barricades.tear(breach)
	var barricade := _night.world.barricade(breach)
	var reach := _night.server.tuning.use_reach
	var x := -reach
	while x <= reach:
		var z := -reach
		while z <= reach:
			var feet := barricade.centre() + Vector3(x, 0.05, z)
			z += 0.25
			if barricade.depth_of(feet) < 0.6 or Vector2(x, z).length() > reach:
				continue
			_night.server.body_of(1).teleport(feet)
			var prompt := _night.server.use_target(1)
			if prompt.get("kind") == &"weapon" and prompt.get("replaces", &"") != &"":
				return feet
		x += 0.25
	return Vector3.INF


func _one(breach: StringName, name: String, at := Vector3.INF) -> void:
	var rules := _night.server.rules
	_night.state.apply_events(rules.apply(RulesAction.grant_points(1, 5000)))
	for _i in rules.tuning.barricades.boards:
		rules.barricades.tear(breach)
	var barricade := _night.world.barricade(breach)
	barricade.set_boards(rules.barricades.boards_of(breach))
	var inward := barricade.inward()
	var player := _night.player()
	var feet := _night.world.repair_spot(breach) if not at.is_finite() else at
	player.teleport(feet + Vector3(0.0, 0.05, 0.0))
	_night.server.body_of(1).teleport(feet + Vector3(0.0, 0.05, 0.0))
	# Looking at the boards, as a person who walked up to mend them.
	var look := barricade.centre() - feet
	player.camera_rig.yaw = atan2(-look.x, -look.z) if at.is_finite() else atan2(inward.x, inward.z)
	player.camera_rig.pitch = -0.08
	player.state.facing = player.camera_rig.yaw
	await _hold(SETTLE)
	await _shot(name)
	var prompt := _night.server.use_target(1)
	print("PROMPT ", name, " ", prompt.get("kind", "none"), " ", prompt.get("id", ""))


func _build(scene: String) -> void:
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	_night = Night.new()
	_night.hud = hud
	_night.scene = load(scene) as PackedScene
	add_child(_night)
	var tuning := RulesFixture.full_hands()
	tuning.rounds.intro_seconds = 600.0
	await _night.start(Night.Mode.HUMAN, 7, tuning)
	await _hold(SETTLE)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(_out.path_join(name + ".png"))
	print("SHOT ", name)


func _hold(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame
