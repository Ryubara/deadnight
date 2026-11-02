class_name ShotRig
extends RefCounted
## Fires the real shot of a real night screen at a wall that stands square across the crosshair, and
## says how far from the crosshair the shot landed on the screen (#601). Nothing here computes a
## shot of its own: the trigger is pressed the way the player presses it (the mouse button's
## action, or a finger on the touch layer's Fire button), the night's tick makes the command from
## the camera, the server fires it, and the shot's end is read from the `shot_fired` event.
##
## What is compared is in canvas units (the HUD's own): where the reticle's centre is drawn, and
## where the camera draws the point the shot ended on. A shot that goes where the reticle shows
## puts the two together whatever the distance, so one tolerance serves close and far.
##
## Two ways to drive it: a suite steps the night by hand (`shoot`), and the browser bench
## (`tests/captures/shot_bench.gd`) lets real touches fire in a running page (`attach`) and reads
## `results`, one entry per shot of the player.

## Ticks given to a shot to come out (a hip shot waits for the body's turn) and to be heard.
const WAIT_TICKS := 90
## The wall is this many metres across: wide enough that no shot misses it by a few degrees.
const WALL_SIZE := 400.0
const WALL_DEPTH := 0.2
## How wide (m) the open ground in front of the player must be.
const CORRIDOR := 3.0
## Ticks a target stands still before the shot, for the client to have seen it there.
const SEEN_TICKS := 12

var night: Night
var screen: NightScreen
var hud: Hud
var touch: bool

## One entry per shot of the player: `{"end", "off", "degrees", "drift"}`, `off` being how far
## (canvas units) the camera drew the shot's end from the reticle, `degrees` the angle between the
## crosshair's ray and the way to the shot's end, both with the view the command was made from (the
## camera as the tick that made the command left it), and `drift` how far the view had turned
## (degrees) between that command and the shot leaving.
var results: Array[Dictionary] = []

var _suite: Node
var _fixture: Variant
var _made := {}
var _walls: Array[StaticBody3D] = []
var _spread_before := 0.0
var _zombie: ZombieBody
var _zombie_at := Vector3.ZERO
var _zones: Array[StringName] = []


## A rig over a night screen that is already running. `fixture`: fingers made by a suite
## (`TouchFixture`, kept untyped because the browser export leaves the test addon out); null when
## real ones touch the page or the input is a mouse.
static func attach(
	host: Node, screen: NightScreen, on_touch: bool, fixture: Variant = null
) -> ShotRig:
	var rig := ShotRig.new()
	rig._suite = host
	rig.touch = on_touch
	rig.screen = screen
	rig.night = screen.night
	rig.hud = screen.find_children("*", "Hud", true, false)[0] as Hud
	rig.night.state.event_received.connect(rig._hear)
	rig.night.ticked.connect(rig._ticked)
	# No mouse to lock here: a lock asked for and never given reads as lost.
	rig.night.player().capture_mouse = false
	rig.night.player().grip.want(false)
	rig._fixture = fixture
	rig._made = rig._view()
	return rig


## The platform's safe area as the touch layer is told it (canvas units): a phone's notch and home
## bar. The HUD keeps inside it.
func safe_area(insets: Vector4) -> void:
	var controls := screen.find_children("*", "TouchControls", true, false)[0] as TouchControls
	controls.insets_override = insets
	controls.refresh()


## The shot judged here has no spread: it is tested apart (`AimResolver`), this asks only where the
## aim goes.
func spread_off() -> void:
	var def := night.server.combat.weapon_of(Night.PLAYER_ID).def
	_spread_before = def.spread_deg
	def.spread_deg = 0.0


## Waits for the first zombie of the night and takes it as the target of `head_on_crosshair`. It
## has a thousand times the health, so a head shot does not end it between one case and the next.
func call_zombie() -> bool:
	# The touch assist pulls the view toward a zombie on purpose (it moves the crosshair itself):
	# the head is put on the dot here and stays there.
	night.assist.strength = 0.0
	night.server.rules.apply(RulesAction.skip_break())
	for _i in 1800:
		night.tick()
		for id: int in night.server.sim.zombies:
			_zombie = night.server.sim.zombies[id]
			var rules_state: ZombieState = night.server.rules._zombies[id]
			rules_state.max_health *= 1000.0
			rules_state.health = rules_state.max_health
			return true
	return false


## Stands the zombie `metres` down the crosshair's ray with its head on the dot, and holds it there
## through the ticks of the shot (`shoot`).
func head_on_crosshair(metres: float) -> void:
	var dot := wall_at(metres)
	clear_walls()
	_zombie_at = dot - Vector3(0.0, Hitbox.ZONES[0]["a"].y, 0.0)
	# The shooter's view of the world is a frame or two old: it sees the zombie stand there first.
	for _i in SEEN_TICKS:
		_hold()
		night.tick()


func _hold() -> void:
	if _zombie != null:
		_zombie.position = _zombie_at
		_zombie.velocity = Vector3.ZERO


## Takes the walls down: a wall left standing stops every shot after it.
func clear_walls() -> void:
	for wall in _walls:
		if is_instance_valid(wall):
			wall.free()
	_walls.clear()


func free_all() -> void:
	if night != null and is_instance_valid(night):
		var def := night.server.combat.weapon_of(Night.PLAYER_ID).def
		if _spread_before > 0.0:
			def.spread_deg = _spread_before
		if night.state.event_received.is_connected(_hear):
			night.state.event_received.disconnect(_hear)
		if night.ticked.is_connected(_ticked):
			night.ticked.disconnect(_ticked)
	clear_walls()
	release()
	if _fixture != null:
		_fixture.free_all()
	TouchMode.device_is_touch = null
	UIInputMode.reset()
	Input.action_release(&"aim")
	Input.action_release(&"fire")


func frames(count: int) -> void:
	for _i in count:
		await _suite.get_tree().process_frame


func camera() -> Camera3D:
	return night.player().camera_rig.get_viewport().get_camera_3d()


## Where the reticle is drawn, in canvas units.
func reticle_centre() -> Vector2:
	return hud.reticle.get_global_rect().get_center()


## Looks `yaw` and `pitch` (radians) the way the player turns the view: the camera rig takes the
## same look a mouse or a thumb gives it.
func look_to(yaw: float, pitch: float) -> void:
	var rig := night.player().camera_rig
	rig.yaw = yaw
	rig.pitch = pitch
	night.player().rotation.y = yaw


## Stands the player where the lot has `metres` of open ground in front, `CORRIDOR` wide, and turns
## the view to it, level: the shoulder camera, the muzzle and the shot stand to either side of the
## line, and a target `metres` away must stand in the lot and not behind its fence or a post. It
## looks round the spot where the player begins, then in a grid of the lot; false when none.
func face_open_ground(metres: float) -> bool:
	var body := night.player()
	var home := body.global_position
	var spots: Array[Vector3] = [home]
	for ring in range(1, 9):
		for step in 8:
			var around := Vector3.FORWARD.rotated(Vector3.UP, TAU * step / 8.0) * float(ring) * 6.0
			spots.append(home + around)
	for spot in spots:
		var yaw := _open_heading(spot, metres)
		if not is_nan(yaw):
			body.teleport(spot)
			look_to(yaw, 0.0)
			return true
	return false


## The heading (radians) with an open corridor from `spot` or NAN.
func _open_heading(spot: Vector3, metres: float) -> float:
	var space := night.get_world_3d().direct_space_state
	var head := spot + Vector3(0.0, 1.5, 0.0)
	var sphere := SphereShape3D.new()
	sphere.radius = CORRIDOR * 0.5
	for turn in range(0, 360, 15):
		var yaw := deg_to_rad(float(turn))
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = sphere
		query.transform = Transform3D(Basis.IDENTITY, head)
		query.motion = Basis.from_euler(Vector3(0.0, yaw, 0.0)) * Vector3.FORWARD * metres
		query.collision_mask = WorldProbe.WORLD_MASK
		var travel := space.cast_motion(query)
		if travel.size() == 2 and travel[0] >= 1.0:
			return yaw
	return NAN


## Holds the aim button (`aimed`) as the player does: the action for a mouse, the Aim button under a
## finger for touch.
func aim(aimed: bool) -> void:
	if touch:
		var at: Vector2 = _fixture.at(TouchLayout.AIM)
		if aimed:
			await _fixture.touch(7, at)
		else:
			await _fixture.lift(7, at)
	elif aimed:
		Input.action_press(&"aim")
	else:
		Input.action_release(&"aim")


func press_fire() -> void:
	if touch:
		await _fixture.touch(8, _fixture.at(TouchLayout.FIRE))
	else:
		Input.action_press(&"fire")


func release() -> void:
	if touch and _fixture != null and _fixture.controls.is_pressed(TouchLayout.FIRE):
		await _fixture.lift(8, _fixture.at(TouchLayout.FIRE))
	Input.action_release(&"fire")


## Puts a wall square across the ray through the reticle, `metres` from the lens, and returns the
## point the reticle is drawn on, on it.
func wall_at(metres: float) -> Vector3:
	clear_walls()
	# (a body joins the physics space on the next physics frame: `settle_wall`)
	var cam := camera()
	var from := cam.project_ray_origin(reticle_centre())
	var toward := cam.project_ray_normal(reticle_centre())
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WALL_SIZE, WALL_SIZE, WALL_DEPTH)
	shape.shape = box
	wall.add_child(shape)
	night.add_child(wall)
	var centre := from + toward * (metres + WALL_DEPTH * 0.5)
	wall.global_transform = Transform3D(Basis.looking_at(toward, Vector3.UP), centre)
	_walls.append(wall)
	return from + toward * metres


## The wall `wall_at` made last, or null.
func last_wall() -> StaticBody3D:
	return _walls[-1] if not _walls.is_empty() else null


## Waits until the physics server has the wall in its space.
func settle_wall() -> void:
	await _suite.get_tree().physics_frame
	await _suite.get_tree().physics_frame


## Fires one shot and answers it (the entry of `results` it made), or `{}` when none came out in
## time.
func shoot() -> Dictionary:
	var shots := results.size()
	_zones.clear()
	await press_fire()
	for _i in WAIT_TICKS:
		await _suite.get_tree().process_frame
		_hold()
		night.tick()
		if results.size() > shots:
			break
	await release()
	var found := {}
	if results.size() > shots:
		found = results[-1]
		found["zones"] = _zones.duplicate()
	# Let the shot's own effects and the weapon's cooldown pass.
	for _i in 40:
		night.tick()
	await frames(2)
	return found


## The camera as the crosshair sees it now: the ray through the reticle, and where it is drawn.
func _view() -> Dictionary:
	var cam := camera()
	var centre := reticle_centre()
	return {
		"transform": cam.global_transform,
		"fov": cam.fov,
		"canvas": cam.get_viewport().get_visible_rect().size,
		"origin": cam.project_ray_origin(centre),
		"ray": cam.project_ray_normal(centre),
		"reticle": centre,
	}


## Where a view draws a world point, in canvas units (the camera keeps the height).
func _drawn(view: Dictionary, point: Vector3) -> Vector2:
	var local: Vector3 = (view["transform"] as Transform3D).affine_inverse() * point
	var canvas: Vector2 = view["canvas"]
	var per_unit := canvas.y * 0.5 / (tan(deg_to_rad(view["fov"]) * 0.5) * -local.z)
	return canvas * 0.5 + Vector2(local.x, -local.y) * per_unit


func _ticked() -> void:
	_made = _view()


func _hear(event: Dictionary) -> void:
	if (
		event.get("type") == &"zombie_damaged"
		and int(event.get("player_id", -1)) == Night.PLAYER_ID
	):
		_zones.append(StringName(str(event.get("zone", ""))))
	if event.get("type") == &"shot_fired" and int(event.get("shooter_id", -1)) == Night.PLAYER_ID:
		results.append(_measure(event["ends"][0]))


## Where the shot that ends at `end` went, against the view its command was made from (`_made`).
func _measure(end: Vector3) -> Dictionary:
	var to_end: Vector3 = (end - (_made["origin"] as Vector3)).normalized()
	var now := _view()
	return {
		"end": end,
		"off": _drawn(_made, end).distance_to(_made["reticle"]),
		"degrees": rad_to_deg(to_end.angle_to(_made["ray"] as Vector3)),
		"drift": rad_to_deg((now["ray"] as Vector3).angle_to(_made["ray"] as Vector3)),
	}
