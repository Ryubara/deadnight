extends Node
## The fence's boards in a night, for captures: the boards whole, the dead coming out of the dark
## and tearing them off (from the field, then from the apron outside), one coming in, then a
## player putting them back from the field side with the HUD's prompt. Only one breach lets the
## dead in, so the camera sees all of it. Not part of the game. Run with Movie Maker:
## `godot --path game res://tests/captures/barricades.tscn --fixed-fps 10 --write-movie out.png`.
## Each stage prints its name and the movie frame it began on.

const BREACH := &"nw"
## Inside the field, looking at the boards.
const FIELD_VIEW_FROM := Vector3(-51.5, 3.2, -40.0)
const FIELD_VIEW_AT := Vector3(-62.0, 1.3, -46.0)
## On the apron, behind the dead at the boards.
const APRON_VIEW_FROM := Vector3(-68.6, 2.6, -43.0)
const APRON_VIEW_AT := Vector3(-62.0, 1.3, -46.0)
## The player at the boards, seen from the field.
const REPAIR_VIEW_FROM := Vector3(-55.0, 2.6, -42.0)
const GIVE_UP_FRAMES := 4000

var _night: Night
var _camera: Camera3D
var _frame_ms: Array[float] = []


func _ready() -> void:
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	_night = Night.new()
	_night.hud = hud
	add_child(_night)
	await _night.start(Night.Mode.MANUAL)
	_camera = Camera3D.new()
	_camera.fov = 62.0
	add_child(_camera)
	_camera.make_current()
	_look(FIELD_VIEW_FROM, FIELD_VIEW_AT)
	var only_here: Array[Vector3] = []
	var gates := _night.world.spawn_gates()
	for point: Vector3 in gates:
		if gates[point] == BREACH:
			only_here.append(point)
	_night.server.director.spawn_points = only_here
	_stage("whole")
	await _hold(25)
	_stage("round_started")
	_act(RulesAction.skip_break())
	await _until(func() -> bool: return _someone_at_the_boards())
	_close(-1.0)
	_stage("close_at_the_boards")
	await _until(func() -> bool: return _boards() < _whole())
	_stage("first_board_torn")
	await _until(func() -> bool: return _boards() < _whole() - 1)
	_stage("second_board_torn")
	await _hold(8)
	_look(APRON_VIEW_FROM, APRON_VIEW_AT)
	_stage("from_the_apron")
	await _until(func() -> bool: return _boards() <= 2)
	_stage("two_boards_left")
	await _hold(5)
	_look(FIELD_VIEW_FROM, FIELD_VIEW_AT)
	await _until(func() -> bool: return _boards() == 0)
	_stage("no_boards")
	await _until(func() -> bool: return _someone_is_in())
	_stage("one_is_in")
	await _hold(10)
	_end_the_round()
	await _until(func() -> bool: return _night.state.phase() == GameRules.Phase.BREAK)
	_night.player().teleport(_night.world.repair_spot(BREACH))
	_look(REPAIR_VIEW_FROM, FIELD_VIEW_AT + Vector3(0.0, 0.4, 0.0))
	_stage("player_at_the_boards")
	await _hold(25)
	_close(1.0)
	_stage("close_repair")
	var use := NightCommand.new()
	use.use = true
	use.motion.yaw = PI / 2.0
	_stage("repairing")
	await _until(
		func() -> bool:
			_night.link.send(use.to_dict())
			return _boards() >= _whole()
	)
	_stage("mended")
	await _hold(30)
	get_tree().quit()


## Close on the boards from the side: outside (`side` -1) on the dead, inside (1) on the player.
func _close(side: float) -> void:
	var barricade := _night.world.barricade(BREACH)
	var inward := barricade.inward()
	var along := inward.cross(Vector3.UP)
	var at := barricade.centre() + inward * side * 0.8 + Vector3(0.0, 1.0, 0.0)
	# Inside, from the side the player stands turned to (along the fence), so the hammering arm shows.
	var out := 3.2 if side < 0.0 else 1.6
	var across := 3.6 if side < 0.0 else -3.0
	_look(at + inward * side * out + along * across + Vector3(0.0, 1.0, 0.0), at)


## A zombie of this breach standing at its boards.
func _someone_at_the_boards() -> bool:
	for zombie: ZombieBody in _night.server.sim.zombies.values():
		if zombie.tearing:
			return true
	return false


func _boards() -> int:
	return _night.world.barricade(BREACH).boards()


func _whole() -> int:
	return _night.server.rules.tuning.barricades.boards


## A zombie that came through this breach and is in the field now.
func _someone_is_in() -> bool:
	var barricade := _night.world.barricade(BREACH)
	for zombie: ZombieBody in _night.server.sim.zombies.values():
		if zombie.gate_id == &"" and barricade.depth_of(zombie.position) > 1.0:
			return true
	return false


## Capture only: the dead are cleared and the round's plan emptied, so the break begins.
func _end_the_round() -> void:
	_night.server.rules._plan.clear()
	for zombie_id: int in _night.server.rules.zombie_ids():
		_act(RulesAction.zombie_gone(zombie_id))


func _look(from: Vector3, at: Vector3) -> void:
	_camera.look_at_from_position(from, at)


func _stage(stage: String) -> void:
	if not _frame_ms.is_empty():
		var total := 0.0
		for ms in _frame_ms:
			total += ms
		print(
			(
				"  frame time since the last stage: mean %.2f ms, worst %.2f ms over %d frames"
				% [total / _frame_ms.size(), _frame_ms.max(), _frame_ms.size()]
			)
		)
		_frame_ms.clear()
	print("%s at frame %d" % [stage, Engine.get_frames_drawn()])


## CPU time of each frame (process and physics), to show the boards' motion keeps it steady.
func _process(_delta: float) -> void:
	_frame_ms.append(
		(
			(
				Performance.get_monitor(Performance.TIME_PROCESS)
				+ Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
			)
			* 1000.0
		)
	)


## A rules action from outside the server's tick, its events delivered as the link would.
func _act(action: Dictionary) -> void:
	_night.state.apply_events(_night.server.rules.apply(action))


func _hold(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame


func _until(done: Callable) -> void:
	for _i in GIVE_UP_FRAMES:
		if done.call():
			return
		await get_tree().physics_frame
	push_error("barricades capture: gave up waiting")
	get_tree().quit()
