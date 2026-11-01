extends Node
## Holding use at a broken breach, from the player's own camera with the HUD (#297): five boards
## down, the player stands at the fence and holds the `interact` action (the key, the pad and the
## touch button all press it) for five seconds; a board goes up every second, then the button
## comes up. Not part of the game. Run with Movie Maker:
## `godot --path game res://tests/captures/repair_hold.tscn --fixed-fps 10
## --write-movie out.png --quit-after 150`.
## Each stage prints its name and the movie frame it began on. `-- --side` films from beside the
## fence instead, with the player's back half turned to the boards at the start (#245: the body
## turns to the boards, and the fist lands as each board knocks home).

const BREACH := &"nw"
## Physics ticks in a second of game time.
const SECOND := 60

var _night: Night


func _ready() -> void:
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = 600.0
	_night = Night.new()
	_night.hud = hud
	add_child(_night)
	await _night.start(Night.Mode.HUMAN, 7, tuning)
	# `-- --before`: one board a press, as it was (no hold), for the before capture.
	if OS.get_cmdline_user_args().has("--before"):
		_night.server.tuning.repair_hold = false
	await _hold(SECOND)
	var rules := _night.server.rules
	for _i in rules.tuning.barricades.boards:
		rules.barricades.tear(BREACH)
	var barricade := _night.world.barricade(BREACH)
	barricade.set_boards(rules.barricades.boards_of(BREACH))
	var inward := barricade.inward()
	var player := _night.player()
	player.teleport(_night.world.repair_spot(BREACH))
	player.camera_rig.yaw = atan2(inward.x, inward.z)
	player.camera_rig.snap_to(player.global_position)
	if OS.get_cmdline_user_args().has("--side"):
		_side_view(player, barricade)
	await _hold(SECOND * 2)
	_stage("standing at the broken fence")
	Input.action_press(&"interact")
	for second in 6:
		_stage("held %d s, %d boards up" % [second, barricade.boards()])
		await _hold(SECOND)
	Input.action_release(&"interact")
	_stage("released, %d boards up" % barricade.boards())
	await _hold(SECOND * 3)
	_stage("end, %d boards up" % barricade.boards())
	get_tree().quit()


## A camera on the field side of the fence, off to one side of the player, looking at him and the
## boards; his back half turned to them.
func _side_view(player: Player, barricade: Barricade) -> void:
	var inward := barricade.inward()
	var along := Vector3.UP.cross(inward).normalized()
	var camera := Camera3D.new()
	camera.fov = 45.0
	add_child(camera)
	camera.global_position = player.global_position + inward * 3.2 + along * 3.4 + Vector3.UP * 1.9
	camera.look_at(player.global_position.lerp(barricade.global_position, 0.4) + Vector3.UP * 1.0)
	camera.make_current()
	var away := player.global_position + inward + along
	var to := away - player.global_position
	player.state.facing = atan2(-to.x, -to.z)


func _stage(stage: String) -> void:
	print("%s at frame %d" % [stage, Engine.get_frames_drawn()])


## Physics ticks of game time (60 a second); the movie takes one frame in six at 10 fps.
func _hold(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame
