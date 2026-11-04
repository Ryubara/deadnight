class_name ArrivalCutscene
extends Node3D
## The arrival of a player by helicopter (#1057), on that player's own screen and nowhere else: a
## camera high above looks down at the lot, a helicopter comes in with its lamp lit and hovers, a
## rope pays out of its door and the player's Soldier, in their own look, slides down it to the
## ground; the screen fades to black and the night is theirs. Nothing here is in the server's night
## or on another client: it is nodes of this client, built when the show begins and freed when it
## ends, over the night that goes on underneath (`ArrivalPlay` keeps the player safe meanwhile).
##
## The helicopter's sound begins in the dark, far off, and closes in with the helicopter: a
## `AudioStreamPlayer3D` on the helicopter under the show's camera, so distance does the rest.
## `ArrivalPlan` says where everything is at each moment; this node only places it.
##
## Steps itself in the physics step (the night's fixed clock: a capture and a test see the same
## show); `advance` steps it by hand.

## The show is over, at black: `skipped` when the player skipped it.
signal finished(skipped: bool)

const HELICOPTER := "res://assets/helicopter/helicopter.gltf"
## The show's names for the pieces of the helicopter model (`assets/helicopter/helicopter.json`).
const MAIN_ROTOR := "MainRotor"
const TAIL_ROTOR := "TailRotor"
const ROPE_ANCHOR := "RopeAnchor"
const SEARCHLIGHT := "Searchlight"
## The nodes of a map that roof the spot the show looks down at: hidden while it plays.
const ROOF_NODES: Array[NodePath] = [^"Ceilings", ^"Roof"]
## The sounds, from the `arrival` bank (on demand: nothing loads them but this show).
const SOUND_LOOP := &"heli_loop"
const SOUND_SLIDE := &"rope_slide"
const SOUND_LAND := &"drop_land"
## The helicopter's loop is this loud (dB under its trim) when it is as near as it comes, and this
## much quieter at the far end of its approach.
const LOOP_NEAR_DB := 0.0
const LOOP_FAR_DB := -20.0
const LOOP_SILENT_DB := -60.0
## How much the helicopter's paint glows (see `_lift_in_the_dark`).
const HULL_GLOW := 0.12
## The rope: a plait about this thick, a warm hemp.
const ROPE_THICKNESS := 0.05
const ROPE_COLOUR := Color(0.55, 0.43, 0.27)
## The lamp's light, and the beam's haze (`beam.gdshader`).
const LAMP_COLOUR := Color(1.0, 0.93, 0.78)
const BEAM_SHADER := "res://world/drive_in/beam.gdshader"
const BEAM_ENERGY := 0.32
const BEAM_SEGMENTS := 20
## The share of the helicopter's lamp range the beam's haze reaches.
const BEAM_REACH := 0.62
## The Soldier's model faces this way (a turn about the vertical, radians) when its node is not
## turned.
const SOLDIER_FACING := 0.0
## How far round from the player's facing the camera stands, radians: in front and to a side, so the
## Soldier's face and the door both read.
const HEADING_TURN := PI * 0.85
## How many headings are tried for a clear view, and how high above the ground the spot's line of
## sight starts (metres).
const HEADING_TRIES := 12
const SIGHT_HEIGHT := 1.6
const CLEAR_LINES := 3
## The bars above and below the picture, as a share of its height.
const BAR_SHARE := 0.075
## The black the picture comes back from after the show, seconds.
const SPAWN_IN_SECONDS := 0.45
## What the corner says once a press would skip, and how far in from the corner it stands (pixels).
const SKIP_HINT := "PRESS ANY BUTTON TO SKIP"
const HINT_MARGIN := 14.0
const HINT_FADE := 0.4
## A skip fades out in this share of the usual fade out.
const SKIP_FADE_SHARE := 0.4

var plan: ArrivalPlan
var tuning: ArrivalTuning
## Seconds into the show.
var clock := 0.0
## Whether the helicopter's lamp and its haze are ever lit (a measurement turns them off to read
## what the light costs).
var lamp_enabled := true
## Whether it steps itself (off, a test or a capture steps it with `advance`).
var self_stepping := true

var _spot := Vector3.ZERO
var _heading := 0.0
var _camera: Camera3D
var _restore: Camera3D
var _heli: Node3D
var _main_rotor: Node3D
var _tail_rotor: Node3D
var _anchor: Node3D
var _lamp: SpotLight3D
var _beam: MeshInstance3D
var _beam_material: ShaderMaterial
var _rope: MeshInstance3D
var _soldier: Node3D
var _pose := ArrivalPose.new()
var _loop: AudioStreamPlayer3D
var _cover: CanvasLayer
var _black: ColorRect
var _hint: UILabel
var _skipping := false
var _skip_clock := 0.0
var _over := false
var _slid := false
var _landed := false
var _spawning := false
var _spawn_clock := 0.0
## What the show took from the lot and gives back: nodes it hid.
var _hidden: Array[Node3D] = []


## Builds the show over `spot` (where the player's body stands in the world) and starts it.
## `facing` is the way the body faces, `look` and `seat` dress the Soldier, `fresh` says whether
## it is the night's opening (a fly-in) or a late join, `restore` the camera to give the view back
## to,
## `hide` the nodes of the lot that would be in the way (a roof over the spot).
func begin(
	p_tuning: ArrivalTuning,
	fresh: bool,
	spot: Vector3,
	facing: float,
	look: CharacterLook,
	seat: int,
	restore: Camera3D,
	hide: Array[Node3D] = []
) -> void:
	tuning = p_tuning
	plan = ArrivalPlan.new(tuning, fresh)
	_spot = spot
	_restore = restore
	_make_camera()
	_make_helicopter()
	_make_rope()
	_make_soldier(look, seat)
	_make_cover()
	_start_sounds()
	for node in hide:
		if node != null and node.visible:
			node.visible = false
			_hidden.append(node)
	_heading = _clear_heading(facing + HEADING_TURN)
	set_physics_process(self_stepping)
	set_process_input(tuning.skippable)
	_place(plan.sample(0.0))


func advance(delta: float) -> void:
	if _over:
		if _spawning:
			_spawn_clock += delta
			_black.color.a = 1.0 - smoothstep(0.0, SPAWN_IN_SECONDS, _spawn_clock)
			if _spawn_clock >= SPAWN_IN_SECONDS:
				queue_free()
		return
	clock += delta
	if _skipping:
		_skip_clock += delta
	_place(plan.sample(minf(clock, plan.seconds())))
	if (_skipping and _skip_clock >= _skip_fade()) or clock >= plan.seconds():
		_finish(_skipping)


func _physics_process(delta: float) -> void:
	advance(delta)


## The turn about the spot the camera stands at (radians), once the show has chosen a clear one.
func heading() -> float:
	return _heading


## The Soldier of the show, or null once it is gone.
func soldier() -> Node3D:
	return _soldier if is_instance_valid(_soldier) else null


## The helicopter of the show, or null once it is gone.
func helicopter() -> Node3D:
	return _heli if is_instance_valid(_heli) else null


## Whether the show is over (it has handed the view back and only the fade out of black is left).
func is_over() -> bool:
	return _over


## Skips the show: it fades out quickly. Refused before `skip_after`, and when it cannot be skipped.
func skip() -> bool:
	if _over or _skipping or not tuning.skippable or clock < tuning.skip_after:
		return false
	_skipping = true
	return true


## Ends the show now, whatever it is up to (the night ended under it): the view goes back and the
## show's nodes are freed at once.
func skip_now() -> void:
	if not _over:
		_finish(true)


## After `finished`: the lot is the player's again, and the black the show left comes away.
func spawn_in() -> void:
	_spawning = true
	_spawn_clock = 0.0
	set_physics_process(self_stepping)


func _input(event: InputEvent) -> void:
	# Esc and a pad's Start are the menu's (`pause`): they open it and skip nothing.
	if not tuning.skippable or _over or event.is_echo() or event.is_action(&"pause"):
		return
	var pressed := false
	if event is InputEventKey:
		pressed = (event as InputEventKey).pressed
	elif event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	elif event is InputEventJoypadButton:
		pressed = (event as InputEventJoypadButton).pressed
	elif event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	if pressed and skip():
		get_viewport().set_input_as_handled()


func _skip_fade() -> float:
	return tuning.fade_out_seconds * SKIP_FADE_SHARE


# --- Building ---


func _make_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "ShowCamera"
	_camera.fov = tuning.camera_fov
	_camera.near = 0.5
	_camera.far = 600.0
	add_child(_camera)
	_camera.make_current()


func _make_helicopter() -> void:
	var scene := load(HELICOPTER) as PackedScene
	_heli = scene.instantiate() as Node3D
	_heli.name = "Helicopter"
	add_child(_heli)
	_main_rotor = _heli.find_child(MAIN_ROTOR, true, false) as Node3D
	_tail_rotor = _heli.find_child(TAIL_ROTOR, true, false) as Node3D
	_anchor = _heli.find_child(ROPE_ANCHOR, true, false) as Node3D
	var lamp_at := _heli.find_child(SEARCHLIGHT, true, false) as Node3D
	_lift_in_the_dark(_heli)
	if _anchor != null:
		plan.anchor = _anchor.position
	_lamp = SpotLight3D.new()
	_lamp.name = "Lamp"
	_lamp.light_color = LAMP_COLOUR
	_lamp.spot_angle = tuning.lamp_angle
	_lamp.spot_range = tuning.lamp_range
	_lamp.light_energy = tuning.lamp_energy
	_lamp.shadow_enabled = false
	lamp_at.add_child(_lamp)
	var reach := tuning.lamp_range * BEAM_REACH
	_beam = MeshInstance3D.new()
	_beam.name = "Beam"
	_beam.mesh = _cone(reach, tan(deg_to_rad(tuning.lamp_angle)) * reach)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam_material = ShaderMaterial.new()
	_beam_material.shader = load(BEAM_SHADER)
	_beam_material.set_shader_parameter(&"tint", LAMP_COLOUR)
	_beam.material_override = _beam_material
	lamp_at.add_child(_beam)


## The helicopter is olive paint on a night lot: its materials glow a little with their own colour,
## so its shape reads from above without a light on it.
func _lift_in_the_dark(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if material == null:
				continue
			var lifted := material.duplicate() as StandardMaterial3D
			lifted.emission_enabled = true
			lifted.emission_texture = lifted.albedo_texture
			lifted.emission = Color.WHITE
			lifted.emission_energy_multiplier = HULL_GLOW
			mesh.set_surface_override_material(surface, lifted)


func _make_rope() -> void:
	_rope = MeshInstance3D.new()
	_rope.name = "Rope"
	var box := BoxMesh.new()
	box.size = Vector3(ROPE_THICKNESS, 1.0, ROPE_THICKNESS)
	var material := StandardMaterial3D.new()
	material.albedo_color = ROPE_COLOUR
	material.roughness = 1.0
	box.material = material
	_rope.mesh = box
	_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rope)


func _make_soldier(look: CharacterLook, seat: int) -> void:
	_soldier = CharacterAssembler.assemble(look, seat)
	_soldier.name = "Soldier"
	add_child(_soldier)
	_pose.setup(_soldier)
	_pose.apply(0.0, 0.0)


func _make_cover() -> void:
	_cover = CanvasLayer.new()
	_cover.name = "ShowCover"
	_cover.layer = 90
	add_child(_cover)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_left = 0.0
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0 - BAR_SHARE
		bar.anchor_bottom = BAR_SHARE if top else 1.0
		_cover.add_child(bar)
	if tuning.skippable:
		_hint = UILabel.new()
		_hint.style = UILabel.Style.CAPTION
		_hint.text = SKIP_HINT
		_hint.modulate.a = 0.0
		_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_hint.offset_right = -HINT_MARGIN
		_hint.offset_bottom = -HINT_MARGIN
		_cover.add_child(_hint)
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover.add_child(_black)
	# The black is over the picture and under the words, which are in the bar.
	if _hint != null:
		_cover.move_child(_hint, _cover.get_child_count() - 1)


func _start_sounds() -> void:
	for id: StringName in [SOUND_LOOP, SOUND_SLIDE, SOUND_LAND]:
		Audio.preload_sound(id)
	_loop = Audio.start_loop(SOUND_LOOP, _heli)
	if _loop != null:
		_loop.volume_db = LOOP_FAR_DB
		_loop.max_db = LOOP_FAR_DB


# --- Where the camera stands ---


## The way round the spot the camera stands (a turn about the vertical): the preferred one, or the
## nearest to it from which nothing solid is between the camera and the spot, the spot and the sky
## the helicopter hangs in, and the camera and where it looks. The drive-in's screen and the small
## map's walls are in the way of some of them.
func _clear_heading(preferred: float) -> float:
	var space := get_world_3d().direct_space_state
	var skip := _hidden_bodies()
	var best := preferred
	var best_clear := -1
	for i in HEADING_TRIES:
		var turn := ceili(i / 2.0) * TAU / HEADING_TRIES * (1.0 if i % 2 == 1 else -1.0)
		var clear := _clear_lines(space, preferred + turn, skip)
		if clear > best_clear:
			best = preferred + turn
			best_clear = clear
		if clear == CLEAR_LINES:
			break
	return best


## How many of the show's lines of sight a heading leaves free (`CLEAR_LINES` when all of them).
func _clear_lines(space: PhysicsDirectSpaceState3D, heading: float, skip: Array[RID]) -> int:
	var turn := Basis(Vector3.UP, heading)
	var chest := _spot + Vector3.UP * SIGHT_HEIGHT
	var eye := _spot + turn * Vector3(0.0, tuning.camera_height, tuning.camera_back)
	var sky := _spot + Vector3.UP * tuning.hover_height
	var free := 0
	for line: Array in [[chest, eye], [eye, sky], [chest, sky]]:
		var query := PhysicsRayQueryParameters3D.create(line[0], line[1], PhysicsLayers.WORLD, skip)
		if space.intersect_ray(query).is_empty():
			free += 1
	return free


## The bodies of the nodes the show hid: they no longer stand in its way.
func _hidden_bodies() -> Array[RID]:
	var found: Array[RID] = []
	for node in _hidden:
		for body in node.find_children("*", "CollisionObject3D", true, false):
			found.append((body as CollisionObject3D).get_rid())
	return found


# --- Stepping ---


## A point of the show's frame, in the world.
func _world(local: Vector3) -> Vector3:
	return _spot + Basis(Vector3.UP, _heading) * local


func _place(shown: ArrivalPlan.Sample) -> void:
	var turn := Basis(Vector3.UP, _heading)
	# The camera.
	_camera.global_position = _world(shown.camera)
	_camera.look_at(_world(shown.target), Vector3.UP)
	_camera.fov = shown.fov
	# The helicopter: nose to the show's +X, its door to the camera. Its origin is put so the rope's
	# anchor is over the spot.
	var nose := Basis(Vector3.UP, -PI * 0.5)
	var lean := Basis(Vector3.RIGHT, shown.heli_pitch) * Basis(Vector3.BACK, shown.heli_roll)
	var anchor_flat := Vector3(plan.anchor.x, 0.0, plan.anchor.z)
	_heli.global_transform = Transform3D(
		turn * nose * lean, _world(shown.heli) - turn * (nose * anchor_flat)
	)
	var spin := clock * tuning.rotor_rps * TAU
	if _main_rotor != null:
		_main_rotor.rotation.y = spin
	if _tail_rotor != null:
		_tail_rotor.rotation.x = spin * 4.0
	# The lamp and its haze.
	var lit := lamp_enabled and shown.lamp > 0.01
	_lamp.visible = lit
	_lamp.light_energy = tuning.lamp_energy * shown.lamp
	_beam.visible = lit
	_beam_material.set_shader_parameter(&"energy", BEAM_ENERGY * shown.lamp)
	# The rope hangs from the anchor to its end; the Soldier rides it.
	var top := _anchor.global_position if _anchor != null else _heli.global_position
	var length := maxf(shown.rope_length, 0.01)
	var sway := turn * Vector3(0.0, 0.0, shown.rope_sway)
	_rope.visible = shown.rope_length > 0.02
	_rope.global_position = top + Vector3.DOWN * length * 0.5 + sway * 0.5
	_rope.scale = Vector3(1.0, length, 1.0)
	_soldier.visible = shown.shown
	_soldier.global_position = Vector3(
		top.x + sway.x, _spot.y + shown.soldier_height, top.z + sway.z
	)
	_soldier.rotation = Vector3(0.0, _heading + SOLDIER_FACING, 0.0)
	_pose.apply(shown.stood, shown.rope_sway * 3.0)
	if shown.shown and not _slid and clock >= plan.slide_start():
		_slid = true
		Audio.play(SOUND_SLIDE, _soldier.global_position)
	if not _landed and clock >= plan.stand_start():
		_landed = true
		Audio.play(SOUND_LAND, _soldier.global_position)
	# The picture and the sound.
	var fade := shown.fade
	if _skipping:
		fade = maxf(fade, smoothstep(0.0, _skip_fade(), _skip_clock))
	_black.color.a = fade
	if _hint != null:
		var ready := smoothstep(tuning.skip_after, tuning.skip_after + HINT_FADE, clock)
		_hint.modulate.a = 0.0 if _skipping else ready * (1.0 - fade)
	if _loop != null:
		var db := lerpf(LOOP_FAR_DB, LOOP_NEAR_DB, shown.sound)
		if _skipping:
			db = lerpf(db, LOOP_SILENT_DB, smoothstep(0.0, _skip_fade(), _skip_clock))
		_loop.volume_db = db
		_loop.max_db = db


## The show is done, at black: the view and the lot go back, and the show's own nodes are freed.
func _finish(skipped: bool) -> void:
	_over = true
	for node in _hidden:
		if is_instance_valid(node):
			node.visible = true
	_hidden.clear()
	if _loop != null:
		_loop.stop()
	if is_instance_valid(_restore):
		_restore.make_current()
	for part: Node in [_camera, _heli, _rope, _soldier]:
		part.queue_free()
	finished.emit(skipped)
	if not _spawning:
		# Nobody asked yet for the fade out of black: it stays until `spawn_in`.
		set_physics_process(false)


## A cone along -Z from its apex at the origin, brightest there (`beam.gdshader` reads the vertex
## colour), its rim `radius` wide at `length`.
func _cone(length: float, radius: float) -> ArrayMesh:
	var vertices := PackedVector3Array([Vector3.ZERO])
	var normals := PackedVector3Array([Vector3.BACK])
	var colours := PackedColorArray([Color(1, 1, 1)])
	var indices := PackedInt32Array()
	for i in BEAM_SEGMENTS:
		var angle := TAU * float(i) / BEAM_SEGMENTS
		vertices.append(Vector3(cos(angle) * radius, sin(angle) * radius, -length))
		normals.append(Vector3(length * cos(angle), length * sin(angle), radius).normalized())
		colours.append(Color(0.05, 0.05, 0.05))
	for i in BEAM_SEGMENTS:
		indices.append_array([0, 1 + i, 1 + (i + 1) % BEAM_SEGMENTS])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
