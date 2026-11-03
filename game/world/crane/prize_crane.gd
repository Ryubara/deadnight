class_name PrizeCrane
extends Node3D
## The drive-in's prize crane: a red cabinet with a glass case full of tiny weapons (one of every
## prize the crane can give), a claw on a gantry, and above the case the prize bay: a lit board
## that the weapons cycle on, and that slides out of the front toward the player with the chosen
## one on it, side on, at the camera's eye height. A marquee and a light beam over it say where it
## stands. Built from boxes in code like the lot's other machines (`MachineParts`); the tiny
## weapons and the prize are the weapons' own models.
##
## It is drawn only from what the server says (`show_state`): the stage (`CraneState.Stage`), the
## seconds left in it and the prize held out. The claw's dig, the cycling, the slide out, the dud
## and the power-down are all functions of those, so a late joiner sees the same crane; only the
## board's slide back in after a play is eased here.
##
## Local space: the front of the glass is +Z, the floor y = 0. Original design, no copied asset.
## The numbers and why the prize sits where it does: `docs/research/mystery-box.md`.

const WIDTH := 1.8
const DEPTH := 1.4
## The red base, the glass case over it, then the prize bay, then the marquee.
const BASE_TOP := 0.85
const GLASS_TOP := 1.55
const BAY_TOP := 2.26
const MARQUEE_TOP := 2.81
## The prize board: its middle's height and size, and how far its face stands in front of the
## cabinet's middle when it is in (behind the front) and when it is out (toward the player). Its
## bottom edge stays over the Soldier's head as the shoulder camera sees it from the crane's
## marker, so the body never covers the prize (`test_crane_view.gd` measures it on the screen).
const BOARD_Y := 1.95
const BOARD_SIZE := Vector2(1.36, 0.46)
const BOARD_IN := 0.42
const BOARD_OUT := 1.12
## The prize's drawn length (m): its length in the hands times `PRIZE_SCALE`, kept between the two,
## so a pistol is still smaller than a rifle but never a speck.
const PRIZE_SCALE := 1.1
const PRIZE_MIN := 0.7
const PRIZE_MAX := 1.2
## The tiny weapons in the case: their length in the hands times `TINY_SCALE`, between the two, and
## how many lie there (every prize at least once, the pool repeated to fill the case).
const TINY_SCALE := 0.5
const TINY_MIN := 0.24
const TINY_MAX := 0.56
const PILE_COUNT := 20
## The case's triangle budget: the 48 plush spheres it replaced were 6,912. Every prize lies there
## once whatever it costs; repeats stop at this.
const PILE_TRIANGLES := 6000
## How much higher the case's floor is at the back than at the front (m).
const PILE_RISE := 0.22
## Where each weapon's hold file is (`PlayerAnimation.HOLDS_DIR`, a test keeps them one): named
## here so a crane does not load the animation's script and the clips it keeps.
const HOLDS_DIR := "res://gameplay/player/holds/"
## The Soldier's own scale: a hold's `model_length x model_scale` times this is its length in hand.
const SOLDIER_SCALE := 0.8
## The weapons' palette; the newest copy holds every older one's cells and the new ones.
const PALETTE := "res://assets/weapons/weapons_palette.png"
## The cell a stand-in tiny weapon is painted with (DarkGrey), as a UV in the palette.
const STAND_IN_UV := Vector2(0.375, 0.125)
## Where a built pile is kept while a crane uses it (the engine's cache holds it weakly), so the
## warm-up's crane and the night's share one: `<this><the pool's hash>`.
const PILE_CACHE := "res://world/crane/pile_"
const CABINET := Color(0.62, 0.1, 0.1)
const CREAM := Color(0.92, 0.85, 0.66)
const SHADOW := Color(0.08, 0.06, 0.06)
const GLASS := Color(0.55, 0.8, 0.9, 0.16)
## The board's light: warm, bright behind the prize so it stands out as a shape.
const BOARD_LIGHT := Color(1.0, 0.86, 0.55)
const BEAM_HEIGHT := 36.0
## The beam's edge fades as the facing of its wall to the eye to this power (a flat additive wall
## has a rim), and the beam nearer the camera than this (metres) fades out.
const BEAM_RIM_POWER := 2.0
const BEAM_NEAR_FADE := 2.5
## The cycling starts this quick (seconds between weapons) and slows to the slow one.
const CYCLE_FAST := 0.07
const CYCLE_SLOW := 0.46
## Seconds the board takes to slide out once the prize is chosen, and to go back in after.
const SLIDE_SECONDS := 0.7
const RETURN_SECONDS := 0.35
## The prize blinks in the last seconds of the grab window.
const BLINK_BELOW := 3.0
const REST_CABLE := 0.1
const DEEP_CABLE := 0.48

var spin_seconds := 4.5
var grab_seconds := 12.0
var leave_seconds := 4.0

var _pool: Array[StringName] = []
## What the build knows of each prize (`_look_up`): its model paths and length in hand.
var _info: Dictionary = {}
var _models: Dictionary = {}
var _pile_ids: Array[StringName] = []
var _drawer: Node3D
var _prize: Node3D
var _dud: Node3D
var _carriage: Node3D
var _cable: MeshInstance3D
var _claw: Node3D
var _prongs: Array[Node3D] = []
var _beam: MeshInstance3D
var _light: OmniLight3D
var _sparks: CPUParticles3D
var _red := StandardMaterial3D.new()
var _cream := StandardMaterial3D.new()
var _glow_material := StandardMaterial3D.new()
var _board_material := StandardMaterial3D.new()
var _beam_material := ShaderMaterial.new()
var _clock := 0.0
var _cycle_left := 0.0
var _cycle_index := 0
var _shown := &""
var _phase := 0
var _lit := 1.0
var _out := 0.0


## `pool` is the shop ids the display cycles through; the times come from `CraneTuning`.
func configure(tuning: CraneTuning, pool: Array[StringName]) -> void:
	spin_seconds = tuning.spin_seconds
	grab_seconds = tuning.grab_seconds
	leave_seconds = tuning.breakdown_seconds
	_pool = pool
	_build()


## Draws one frame of the crane: `crane` is the server frame's `crane` ({stage, left, weapon, ...}),
## `delta` the seconds since the last call.
func show_state(crane: Dictionary, delta: float) -> void:
	_clock += delta
	_phase = int(crane.get("stage", CraneState.Stage.READY))
	var left := float(crane.get("left", 0.0))
	var weapon := StringName(crane.get("weapon", &""))
	match _phase:
		CraneState.Stage.SPIN:
			_spin(1.0 - left / maxf(spin_seconds, 0.01), delta)
		CraneState.Stage.GRAB:
			_grab(weapon, grab_seconds - left, left)
		CraneState.Stage.LEAVING:
			_leave(1.0 - left / maxf(leave_seconds, 0.01), leave_seconds - left)
		_:
			_rest(delta)
	_drawer.position.z = lerpf(BOARD_IN, BOARD_OUT, _out)
	_light.light_energy = 1.1 * _lit
	_glow_material.emission_energy_multiplier = 1.4 * _lit
	_beam.visible = _phase != CraneState.Stage.LEAVING or _lit > 0.05
	_beam_material.set_shader_parameter(&"strength", _lit)


## The weapon on the board now (`&""` for none), for tests and tools.
func shown_weapon() -> StringName:
	return _shown if _prize.visible else &""


func dud_visible() -> bool:
	return _dud.visible


func beam_visible() -> bool:
	return _beam.visible


## How far the board is out of the front: 0 in, 1 all the way out toward the player.
func prize_out() -> float:
	return _out


## The node the prize is drawn under (one holder per prize, the shown one visible).
func prize_node() -> Node3D:
	return _prize


## The shop ids of the tiny weapons in the case, one entry for each that lies there.
func pile_weapons() -> Array[StringName]:
	return _pile_ids


## The mesh the tiny weapons are merged into (one draw call), or null with an empty pool.
func pile_mesh() -> ArrayMesh:
	var node := get_node_or_null(^"Pile") as MeshInstance3D
	return node.mesh as ArrayMesh if node != null else null


## The weapon's model in the hands (`holds/<id>.tres`), or `""` while it has none: then the crane
## draws a stand-in. A weapon added to the pool with its hold file needs nothing here.
static func model_of(shop_id: StringName) -> String:
	return String(_look_up(shop_id)["near"])


## The far level of the weapon's model (`<model>_far.glb` beside it), or `""` when there is none.
static func far_model_of(shop_id: StringName) -> String:
	return String(_look_up(shop_id)["far"])


## The weapon's model and far level, and its length in the Soldier's hands (m, 0 without a hold).
## One `load` of the hold: a cached `load` still costs about a millisecond.
static func _look_up(shop_id: StringName) -> Dictionary:
	var info := {"near": "", "far": "", "length": 0.0, "upright": false}
	var path := HOLDS_DIR + String(WeaponCatalog.catalog_id(shop_id)) + ".tres"
	if not ResourceLoader.exists(path):
		return info
	var hold := load(path) as WeaponHold
	if hold == null or not hold.has_model():
		return info
	info["near"] = hold.scene
	# A melee weapon is modelled standing, its head up; a gun lies along its muzzle.
	info["upright"] = not hold.shouldered
	info["length"] = hold.model_length * hold.model_scale * SOLDIER_SCALE
	var far := hold.scene.get_basename() + "_far.glb"
	info["far"] = far if ResourceLoader.exists(far) else ""
	return info


func _length(shop_id: StringName, fallback: float) -> float:
	var length := float(_info[shop_id]["length"])
	return length if length > 0.0 else fallback


## Ready: the claw idles, the board goes back in empty.
func _rest(delta: float) -> void:
	_lit = 1.0
	_sparks.emitting = false
	_dud.visible = false
	_out = maxf(_out - delta / RETURN_SECONDS, 0.0)
	_show_weapon(&"")
	_board_material.emission_energy_multiplier = 0.9
	_place_claw(0.0, REST_CABLE + 0.02 * sin(_clock * 1.3), 0.7)


## The dig: sweep over the pile, drop, close, lift; the weapons cycle on the board, slowing down,
## and the board's light beats with them.
func _spin(t: float, delta: float) -> void:
	_lit = 1.0
	_sparks.emitting = false
	_dud.visible = false
	_out = 0.0
	var sweep := smoothstep(0.0, 0.3, t)
	var drop := smoothstep(0.25, 0.5, t) - smoothstep(0.65, 0.9, t)
	var closing := smoothstep(0.5, 0.62, t)
	_place_claw(lerpf(-0.45, 0.25, sweep), lerpf(REST_CABLE, DEEP_CABLE, drop), 1.0 - closing * 0.8)
	_cycle_left -= delta
	if _cycle_left <= 0.0 and not _pool.is_empty():
		_cycle_index += 1
		_show_weapon(_pool[_cycle_index % _pool.size()])
		_cycle_left = lerpf(CYCLE_FAST, CYCLE_SLOW, t * t)
	_board_material.emission_energy_multiplier = 1.0 + 0.5 * float(_cycle_index % 2)
	_hold_still(0.0)


## The prize chosen: the board slides out of the front toward the player, stops with a small
## bump, and holds the prize side on for the window; it blinks as the window runs out.
func _grab(weapon: StringName, elapsed: float, left: float) -> void:
	_lit = 1.0
	_sparks.emitting = false
	_dud.visible = false
	_show_weapon(weapon)
	_out = _slide(elapsed)
	_place_claw(lerpf(0.25, 0.0, _out), lerpf(DEEP_CABLE * 0.5, REST_CABLE, _out), 0.2)
	_hold_still(1.0)
	var blink := left <= BLINK_BELOW and int(_clock * 7.0) % 2 == 1
	_prize.visible = _shown != &"" and not blink
	_board_material.emission_energy_multiplier = 0.4 if blink else 1.1


## The dud: the board slides out with a moth-eaten plush on it, sparks, a flicker, then the power
## goes.
func _leave(t: float, elapsed: float) -> void:
	_show_weapon(&"")
	_dud.visible = true
	_dud.rotation.z = 0.12 * sin(_clock * 3.0)
	_out = _slide(elapsed)
	_sparks.emitting = t < 0.8
	var flicker := 0.5 + 0.5 * sin(_clock * 37.0) * sin(_clock * 11.0)
	_lit = clampf(1.0 - smoothstep(0.55, 0.95, t), 0.0, 1.0) * (0.45 + 0.55 * flicker)
	_board_material.emission_energy_multiplier = 1.4 * _lit
	_place_claw(0.1, lerpf(0.4, REST_CABLE, t), 1.0)


## How far out the board is `elapsed` seconds after it starts to slide: out in `SLIDE_SECONDS`,
## with a small bump at the end as it stops.
func _slide(elapsed: float) -> float:
	var t := clampf(elapsed / SLIDE_SECONDS, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - t, 3.0)
	return clampf(eased + 0.06 * sin(t * PI), 0.0, 1.0)


## The prize on the board turns a little to catch the light, never round to its end.
func _hold_still(amount: float) -> void:
	_prize.rotation.y = 0.12 * amount * sin(_clock * 1.6)
	_prize.position.y = 0.012 * amount * sin(_clock * 2.2)


func _place_claw(x: float, cable: float, open: float) -> void:
	_carriage.position = Vector3(x, GLASS_TOP - 0.07, 0.0)
	_cable.scale = Vector3(1.0, cable, 1.0)
	_cable.position = Vector3(0.0, -cable * 0.5, 0.0)
	_claw.position = Vector3(0.0, -cable, 0.0)
	for i in _prongs.size():
		var spread := deg_to_rad(10.0 + 35.0 * open)
		_prongs[i].rotation = Vector3(0.0, TAU * i / _prongs.size(), 0.0)
		(_prongs[i].get_child(0) as Node3D).rotation.z = -spread


## Shows the model of `weapon_id` on the board (nothing for `&""`).
func _show_weapon(weapon_id: StringName) -> void:
	if weapon_id == _shown:
		return
	_shown = weapon_id
	for id: StringName in _models:
		(_models[id] as Node3D).visible = id == weapon_id
	_prize.visible = weapon_id != &""


# --- Building ---


func _build() -> void:
	for child in get_children():
		child.queue_free()
	_prongs.clear()
	_models.clear()
	_info.clear()
	for id in _pool:
		_info[id] = _look_up(id)
	_out = 0.0
	_red = MachineParts.plain(CABINET)
	_cream = MachineParts.plain(CREAM)
	var parts := StaticParts.new()
	_cabinet(parts)
	_gantry(parts)
	parts.commit(self)
	_drawer_board()
	_pile()
	_prizes()
	_dud_plush()
	_effects()
	_cycle_left = 0.0
	_shown = &"?"
	_show_weapon(&"")


func _cabinet(parts: StaticParts) -> void:
	var dark := MachineParts.plain(SHADOW)
	var front := DEPTH / 2.0
	parts.box(_red, Vector3(WIDTH, BASE_TOP, DEPTH), Vector3(0.0, BASE_TOP / 2.0, 0.0))
	# The case's floor, cream, so the tiny weapons (grey, wood, black) stand out on it, rising to
	# the back so the back rows show over the front ones.
	var floor_depth := DEPTH - 0.06
	var tilt := Basis(Vector3.RIGHT, atan2(PILE_RISE, floor_depth))
	var floor_size := Vector3(WIDTH - 0.06, 0.02, floor_depth / cos(atan2(PILE_RISE, floor_depth)))
	parts.box_at(
		_cream,
		Transform3D(
			tilt * Basis.from_scale(floor_size), Vector3(0.0, BASE_TOP + PILE_RISE / 2.0, 0.0)
		)
	)
	parts.box(_cream, Vector3(WIDTH + 0.08, 0.1, DEPTH + 0.08), Vector3(0.0, 0.05, 0.0))
	# A coin door and a strip of trim on the base's front.
	parts.box(_cream, Vector3(0.34, 0.26, 0.04), Vector3(-0.5, 0.48, front + 0.02))
	parts.box(dark, Vector3(0.05, 0.1, 0.02), Vector3(-0.5, 0.5, front + 0.045))
	parts.box(_cream, Vector3(WIDTH + 0.02, 0.05, 0.04), Vector3(0.0, BASE_TOP - 0.03, front))
	# The prize bay: a red frame round an opening the board slides out of, dark inside.
	var bay_height := BAY_TOP - GLASS_TOP
	var bay_y := GLASS_TOP + bay_height / 2.0
	var opening := BOARD_SIZE + Vector2(0.06, 0.06)
	var side := (WIDTH - opening.x) / 2.0
	for side_sign: float in [-1.0, 1.0]:
		parts.box(
			_red,
			Vector3(side, bay_height, DEPTH),
			Vector3(side_sign * (opening.x + side) / 2.0, bay_y, 0.0)
		)
	var below := BOARD_Y - opening.y / 2.0 - GLASS_TOP
	parts.box(_red, Vector3(opening.x, below, DEPTH), Vector3(0.0, GLASS_TOP + below / 2.0, 0.0))
	var above := BAY_TOP - (BOARD_Y + opening.y / 2.0)
	parts.box(_red, Vector3(opening.x, above, DEPTH), Vector3(0.0, BAY_TOP - above / 2.0, 0.0))
	parts.box(dark, Vector3(opening.x, opening.y, 0.04), Vector3(0.0, BOARD_Y, -front + 0.1))
	# A cream lip round the opening, so the hole reads as a door in the machine.
	var lip := opening + Vector2(0.08, 0.08)
	for y: float in [BOARD_Y - lip.y / 2.0 + 0.02, BOARD_Y + lip.y / 2.0 - 0.02]:
		parts.box(_cream, Vector3(lip.x, 0.04, 0.05), Vector3(0.0, y, front + 0.01))
	for x: float in [-lip.x / 2.0 + 0.02, lip.x / 2.0 - 0.02]:
		parts.box(_cream, Vector3(0.04, lip.y, 0.05), Vector3(x, BOARD_Y, front + 0.01))
	# The marquee, lit, and its cornice.
	_glow_material = MachineParts.glow(Color(1.0, 0.9, 0.6), 1.4)
	_glow_material.emission = Color(1.0, 0.85, 0.5)
	MachineParts.box(
		self,
		"Marquee",
		Vector3(WIDTH + 0.1, MARQUEE_TOP - BAY_TOP, DEPTH + 0.1),
		Vector3(0.0, (BAY_TOP + MARQUEE_TOP) / 2.0, 0.0),
		_glow_material
	)
	parts.box(
		_cream, Vector3(WIDTH + 0.2, 0.08, DEPTH + 0.2), Vector3(0.0, MARQUEE_TOP + 0.04, 0.0)
	)
	MachineParts.label(
		self,
		"PRIZE CRANE",
		Vector3(0.0, (BAY_TOP + MARQUEE_TOP) / 2.0, front + 0.07),
		64,
		Color(1.0, 0.92, 0.6),
		Color(0.25, 0.04, 0.04)
	)
	# Glass: four panes round the case, see-through, and the case's corner posts.
	var pane := StandardMaterial3D.new()
	pane.albedo_color = GLASS
	pane.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pane.cull_mode = BaseMaterial3D.CULL_DISABLED
	var height := GLASS_TOP - BASE_TOP
	var glass_y := BASE_TOP + height / 2.0
	parts.box(pane, Vector3(WIDTH, height, 0.03), Vector3(0.0, glass_y, front))
	parts.box(pane, Vector3(WIDTH, height, 0.03), Vector3(0.0, glass_y, -front))
	parts.box(pane, Vector3(0.03, height, DEPTH), Vector3(WIDTH / 2.0, glass_y, 0.0))
	parts.box(pane, Vector3(0.03, height, DEPTH), Vector3(-WIDTH / 2.0, glass_y, 0.0))
	for x: float in [-WIDTH / 2.0, WIDTH / 2.0]:
		for z: float in [-front, front]:
			parts.box(_cream, Vector3(0.06, height, 0.06), Vector3(x, glass_y, z))
	# No collision: this is a drawing. The wall is the world's (`CraneBlock`), the same on a server.


func _gantry(parts: StaticParts) -> void:
	parts.box(_cream, Vector3(WIDTH - 0.1, 0.05, 0.05), Vector3(0.0, GLASS_TOP - 0.03, 0.0))
	_carriage = Node3D.new()
	add_child(_carriage)
	var steel := MachineParts.plain(Color(0.7, 0.7, 0.75))
	MachineParts.box(_carriage, "Carriage", Vector3(0.22, 0.08, 0.16), Vector3.ZERO, _cream)
	_cable = MachineParts.cylinder(
		_carriage,
		"Cable",
		0.012,
		1.0,
		Vector3.ZERO,
		MachineParts.plain(Color(0.15, 0.15, 0.17)),
		Vector3.AXIS_Y,
		6
	)
	_claw = Node3D.new()
	_carriage.add_child(_claw)
	MachineParts.sphere(_claw, "Hub", 0.06, Vector3.ZERO, steel)
	for i in 3:
		var pivot := Node3D.new()
		var arm := Node3D.new()
		MachineParts.box(arm, "Finger", Vector3(0.025, 0.2, 0.025), Vector3(0, -0.1, 0), steel)
		arm.position = Vector3(0.05, 0.0, 0.0)
		pivot.add_child(arm)
		_claw.add_child(pivot)
		_prongs.append(pivot)


## The drawer the prize comes out on: a red body with a lit board for a face, framed in cream with
## a shelf under it. It moves along Z (`BOARD_IN` to `BOARD_OUT`); the prize hangs on its face.
func _drawer_board() -> void:
	_drawer = Node3D.new()
	_drawer.name = "Drawer"
	_drawer.position = Vector3(0.0, BOARD_Y, BOARD_IN)
	add_child(_drawer)
	var parts := StaticParts.new()
	var depth := 0.5
	parts.box(_red, Vector3(BOARD_SIZE.x, BOARD_SIZE.y, depth), Vector3(0.0, 0.0, -depth / 2.0))
	parts.box(
		_cream, Vector3(BOARD_SIZE.x + 0.04, 0.04, 0.14), Vector3(0.0, -BOARD_SIZE.y / 2.0, 0.05)
	)
	parts.box(
		_cream, Vector3(BOARD_SIZE.x + 0.04, 0.03, 0.05), Vector3(0.0, BOARD_SIZE.y / 2.0, 0.01)
	)
	for x: float in [-BOARD_SIZE.x / 2.0, BOARD_SIZE.x / 2.0]:
		parts.box(_cream, Vector3(0.04, BOARD_SIZE.y + 0.04, 0.05), Vector3(x, 0.0, 0.01))
	parts.commit(_drawer)
	_board_material = MachineParts.glow(BOARD_LIGHT, 1.0)
	MachineParts.box(
		_drawer,
		"Board",
		Vector3(BOARD_SIZE.x - 0.04, BOARD_SIZE.y - 0.04, 0.02),
		Vector3.ZERO,
		_board_material
	)
	_prize = Node3D.new()
	_prize.name = "Prize"
	_drawer.add_child(_prize)


## The tiny weapons lying in the case: the far model of every prize in the pool, then the pool
## again while the case has room (`PILE_COUNT`) and triangles to spare (`PILE_TRIANGLES`), merged
## into one mesh with the weapons' palette, so the case is one draw call. A prize with no model yet
## lies there as a plain dark stand-in.
func _pile() -> void:
	_pile_ids.clear()
	if _pool.is_empty():
		return
	var cached := PILE_CACHE + str(hash(",".join(_pool)))
	var mesh: ArrayMesh = null
	if ResourceLoader.has_cached(cached):
		mesh = ResourceLoader.get_cached_ref(cached) as ArrayMesh
	if mesh == null:
		mesh = _pile_mesh()
		mesh.take_over_path(cached)
	_pile_ids.assign(mesh.get_meta(&"pile_ids", []))
	var node := MeshInstance3D.new()
	node.name = "Pile"
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


## The case floor's height at `z` (it rises to the back by `PILE_RISE`).
static func _floor_y(z: float) -> float:
	var back := clampf(0.5 - z / (DEPTH - 0.06), 0.0, 1.0)
	return BASE_TOP + 0.02 + PILE_RISE * back


func _pile_mesh() -> ArrayMesh:
	# Each prize's tiny model once: its surfaces fitted to its tiny length, and its triangles.
	var tiny := {}
	var material: Material = null
	for id in _pool:
		var length := clampf(_length(id, 0.6) * TINY_SCALE, TINY_MIN, TINY_MAX)
		var parts: Array = []
		var triangles := 12
		var far := String(_info[id]["far"])
		var scene: PackedScene = load(far) if far != "" else null
		if scene != null:
			triangles = 0
			var model := scene.instantiate() as Node3D
			var fitted := _fitted(model, length, bool(_info[id]["upright"]))
			for node: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
				for surface in node.mesh.get_surface_count():
					if material == null:
						material = node.mesh.surface_get_material(surface)
					parts.append([node.mesh, surface, fitted * _to_root(node, model)])
					triangles += MeshMerge.triangles(node.mesh, surface)
			model.free()
		tiny[id] = {"length": length, "parts": parts, "triangles": triangles}
	var ids: Array[StringName] = _pool.duplicate()
	var total := 0
	for id in ids:
		total += int(tiny[id]["triangles"])
	var next := 0
	while ids.size() < PILE_COUNT:
		var id := _pool[next % _pool.size()]
		if total + int(tiny[id]["triangles"]) > PILE_TRIANGLES:
			break
		ids.append(id)
		total += int(tiny[id]["triangles"])
		next += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 1958
	var merged := MeshMerge.new()
	var columns := 4
	var rows := ceili(float(ids.size()) / columns)
	var cell := Vector2((WIDTH - 0.3) / columns, (DEPTH - 0.3) / rows)
	for i in ids.size():
		var info: Dictionary = tiny[ids[i]]
		var length := float(info["length"])
		var z := -(DEPTH - 0.3) / 2.0 + cell.y * (0.5 + i / columns) + rng.randf_range(-0.05, 0.05)
		var spot := Vector3(
			-(WIDTH - 0.3) / 2.0 + cell.x * (0.5 + i % columns) + rng.randf_range(-0.06, 0.06),
			_floor_y(z) + length * 0.16 + rng.randf_range(0.0, 0.05),
			z
		)
		# Side on to the glass (either way round, turned a little), leaning on its neighbours, as
		# prizes are heaped in a crane: a front view reads each one's shape.
		var place := Transform3D(
			(
				Basis(Vector3.UP, PI * float(i % 2) + rng.randf_range(-0.6, 0.6))
				* Basis(Vector3.RIGHT, rng.randf_range(-0.45, 0.45))
				* Basis(Vector3.BACK, rng.randf_range(-0.3, 0.3))
			),
			spot
		)
		if (info["parts"] as Array).is_empty():
			var size := Vector3(length, length * 0.25, length * 0.1)
			merged.box(place * Transform3D(Basis.from_scale(size), Vector3.ZERO), STAND_IN_UV)
			continue
		for part: Array in info["parts"]:
			merged.add(part[0], part[1], place * (part[2] as Transform3D))
	var palette_material := StandardMaterial3D.new()
	if material is StandardMaterial3D:
		palette_material = (material as StandardMaterial3D).duplicate() as StandardMaterial3D
	else:
		palette_material.roughness = 0.415
		palette_material.metallic = 0.4
		palette_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	palette_material.albedo_texture = load(PALETTE)
	var mesh := merged.commit(palette_material)
	mesh.set_meta(&"pile_ids", ids)
	return mesh


## The prizes on the board: one holder per weapon of the pool, its own model fitted side on, the
## muzzle to the player's right and the gun's right side toward them. A prize with no model yet is
## a plain silhouette.
func _prizes() -> void:
	for id in _pool:
		var holder := Node3D.new()
		holder.name = String(id)
		var path := String(_info[id]["near"])
		var scene: PackedScene = load(path) if path != "" else null
		var length := clampf(_length(id, 1.0) * PRIZE_SCALE, PRIZE_MIN, PRIZE_MAX)
		if scene != null:
			var model := scene.instantiate() as Node3D
			holder.add_child(model)
			var turn := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
			model.transform = turn * _fitted(model, length, bool(_info[id]["upright"]))
		else:
			var stand_in := _silhouette(id)
			stand_in.scale = Vector3.ONE * length / 1.3
			holder.add_child(stand_in)
		holder.position = Vector3(0.0, 0.0, 0.09)
		holder.visible = false
		_prize.add_child(holder)
		_models[id] = holder


## A plain stand-in for a weapon with no model yet: a body, a barrel and a grip, in one colour.
func _silhouette(id: StringName) -> Node3D:
	var node := Node3D.new()
	var small := id == &"weapon_flare_gun"
	var colour := Color(0.95, 0.5, 0.15) if small else Color(0.3, 0.38, 0.3)
	var length := 0.7 if small else 1.3
	var body := MachineParts.plain(colour)
	MachineParts.box(node, "Body", Vector3(length, 0.12, 0.07), Vector3.ZERO, body)
	MachineParts.box(
		node, "Barrel", Vector3(length * 0.55, 0.05, 0.05), Vector3(length * 0.7, 0.01, 0.0), body
	)
	MachineParts.box(
		node,
		"Grip",
		Vector3(0.09, 0.2, 0.06),
		Vector3(-length * 0.3, -0.14, 0.0),
		MachineParts.plain(colour.darkened(0.2))
	)
	return node


## The dud prize: a plush bear with moth holes, one ear half off and an eye hanging by a thread,
## sitting on the board's shelf.
func _dud_plush() -> void:
	_dud = Node3D.new()
	_dud.name = "Dud"
	_dud.visible = false
	_dud.position = Vector3(0.0, -0.02, 0.16)
	_dud.scale = Vector3.ONE * 0.62
	_drawer.add_child(_dud)
	var fur := MachineParts.plain(Color(0.5, 0.4, 0.3))
	var worn := MachineParts.plain(Color(0.4, 0.32, 0.24))
	var black := MachineParts.plain(Color(0.05, 0.05, 0.05))
	var hole := MachineParts.plain(Color(0.04, 0.03, 0.03))
	MachineParts.sphere(_dud, "Body", 0.26, Vector3(0.0, -0.1, 0.0), fur)
	MachineParts.sphere(_dud, "Head", 0.19, Vector3(0.0, 0.2, 0.0), fur)
	MachineParts.sphere(_dud, "Ear", 0.08, Vector3(-0.15, 0.36, 0.0), fur)
	MachineParts.sphere(_dud, "TornEar", 0.08, Vector3(0.2, 0.32, 0.0), worn)
	MachineParts.sphere(_dud, "Eye", 0.035, Vector3(-0.07, 0.23, 0.17), black)
	MachineParts.sphere(_dud, "LooseEye", 0.035, Vector3(0.1, 0.17, 0.17), black)
	var holes: Array[Vector3] = [
		Vector3(0.1, -0.05, 0.24), Vector3(-0.12, -0.18, 0.23), Vector3(0.0, -0.27, 0.2)
	]
	for at in holes:
		MachineParts.sphere(_dud, "Hole", 0.045, at, hole)
	MachineParts.sphere(_dud, "Arm", 0.09, Vector3(0.27, -0.15, 0.0), worn)


func _effects() -> void:
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.8, 0.5)
	# Just in front of the board when it is out, so the prize's face is lit. Its reach is 4.6 m (5
	# before): further forward or wider, it reaches a roof or a floor of the stand that the lot's
	# light budget has no room on (`test_lot_light_cap.gd`).
	_light.omni_range = 4.6
	_light.position = Vector3(0.0, 1.7, BOARD_OUT + 0.18)
	add_child(_light)
	_sparks = CPUParticles3D.new()
	_sparks.amount = 36
	_sparks.lifetime = 0.6
	_sparks.explosiveness = 0.2
	_sparks.direction = Vector3(0.0, 1.0, 0.4)
	_sparks.spread = 70.0
	_sparks.initial_velocity_min = 1.5
	_sparks.initial_velocity_max = 3.5
	_sparks.gravity = Vector3(0.0, -7.0, 0.0)
	_sparks.scale_amount_min = 0.5
	_sparks.scale_amount_max = 1.0
	# A spark is a small box, 12 triangles: a default sphere was 4,000 (145,000 for the shower).
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3.ONE * 0.035
	var spark_material := StandardMaterial3D.new()
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.albedo_color = Color(1.0, 0.85, 0.4)
	spark_mesh.material = spark_material
	_sparks.mesh = spark_mesh
	_sparks.position = Vector3(0.0, BOARD_Y + BOARD_SIZE.y / 2.0, DEPTH / 2.0)
	_sparks.emitting = false
	add_child(_sparks)
	_beam = _make_beam()
	add_child(_beam)


## The light beam: an open cone from the cabinet's top, brightest at the foot, fading up, added to
## the picture. It starts over the marquee, so it never lies over the prize.
func _make_beam() -> MeshInstance3D:
	var shader := Shader.new()
	shader.code = (
		"""
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.45, 0.8, 1.0, 0.32);
uniform float strength = 1.0;
// The beam is soft at its edge and gone from a camera that is in it: a flat additive wall with a
// rim reads as a solid column from the shoulder camera (#854).
uniform float rim_power = 0.0;
uniform float near_fade = 0.0;
varying float up;
void vertex() { up = clamp(0.5 + VERTEX.y / %f, 0.0, 1.0); }
void fragment() {
	float fade = pow(1.0 - up, 1.4);
	float face = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float soft = pow(face, rim_power);
	if (near_fade > 0.0) {
		soft *= smoothstep(0.2 * near_fade, near_fade, -VERTEX.z);
	}
	ALBEDO = tint.rgb;
	ALPHA = tint.a * fade * strength * soft;
}
"""
		% BEAM_HEIGHT
	)
	_beam_material = ShaderMaterial.new()
	_beam_material.shader = shader
	_beam_material.set_shader_parameter(&"rim_power", BEAM_RIM_POWER)
	_beam_material.set_shader_parameter(&"near_fade", BEAM_NEAR_FADE)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.18
	cone.bottom_radius = 0.95
	cone.height = BEAM_HEIGHT
	cone.radial_segments = 16
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	var node := MeshInstance3D.new()
	node.mesh = cone
	node.material_override = _beam_material
	node.position = Vector3(0.0, MARQUEE_TOP + BEAM_HEIGHT / 2.0, 0.0)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## The transform that lays `model` along X, its longest side `length` metres, centred: a gun as it
## is modelled (muzzle -X, up +Y), an `upright` one (a melee weapon, modelled standing with its
## head up) laid down with the head toward -X, where a gun's muzzle is.
static func _fitted(model: Node3D, length: float, upright: bool) -> Transform3D:
	var box := _bounds(model, Transform3D.IDENTITY)
	if box.size == Vector3.ZERO:
		return Transform3D.IDENTITY
	var turn := box.size.z > box.size.x
	var longest := maxf(maxf(box.size.x, box.size.z), box.size.y)
	var factor := length / maxf(longest, 0.001)
	var lay := (
		Basis(Vector3.BACK, PI * 0.5) if upright else Basis(Vector3.UP, PI * 0.5 if turn else 0.0)
	)
	var basis := lay * Basis.from_scale(Vector3.ONE * factor)
	return Transform3D(basis, -(basis * box.get_center()))


## The box round every mesh under `node`, in the space of the model's root.
static func _bounds(node: Node, to_root: Transform3D) -> AABB:
	var box := AABB()
	var first := true
	if node is MeshInstance3D:
		box = to_root * (node as MeshInstance3D).get_aabb()
		first = false
	for child in node.get_children():
		if child is Node3D:
			var inner := _bounds(child, to_root * (child as Node3D).transform)
			if inner.size != Vector3.ZERO:
				box = inner if first else box.merge(inner)
				first = false
	return box


## `node`'s transform in the space of `root`, an ancestor.
static func _to_root(node: Node3D, root: Node3D) -> Transform3D:
	var to := Transform3D.IDENTITY
	var at: Node = node
	while at != root and at is Node3D:
		to = (at as Node3D).transform * to
		at = at.get_parent()
	return to


## Boxes that never move, gathered by material and drawn as one mesh per material.
class StaticParts:
	var _by_material: Dictionary = {}

	func box(material: Material, size: Vector3, at: Vector3) -> void:
		box_at(material, Transform3D(Basis.from_scale(size), at))

	## A unit box moved (scaled, turned) by `xform`.
	func box_at(material: Material, xform: Transform3D) -> void:
		var merge: MeshMerge = _by_material.get(material)
		if merge == null:
			merge = MeshMerge.new()
			_by_material[material] = merge
		merge.box(xform, Vector2(-1.0, -1.0))

	func commit(parent: Node3D) -> void:
		var index := 0
		for material: Material in _by_material:
			var node := MeshInstance3D.new()
			node.name = "Static%d" % index
			node.mesh = (_by_material[material] as MeshMerge).commit(material)
			parent.add_child(node)
			index += 1


## Triangles gathered from meshes and boxes into one surface: positions, normals, UVs, indices.
class MeshMerge:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	## Appends surface `surface` of `mesh`, moved by `xform`.
	func add(mesh: Mesh, surface: int, xform: Transform3D) -> void:
		var arrays := mesh.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms := PackedVector3Array()
		if arrays[Mesh.ARRAY_NORMAL] != null:
			norms = arrays[Mesh.ARRAY_NORMAL]
		var coords := PackedVector2Array()
		if arrays[Mesh.ARRAY_TEX_UV] != null:
			coords = arrays[Mesh.ARRAY_TEX_UV]
		var turn := xform.basis.inverse().transposed()
		var start := vertices.size()
		for i in points.size():
			vertices.append(xform * points[i])
			normals.append((turn * norms[i]).normalized() if i < norms.size() else Vector3.UP)
			uvs.append(coords[i] if i < coords.size() else Vector2.ZERO)
		if arrays[Mesh.ARRAY_INDEX] == null:
			for i in points.size():
				indices.append(start + i)
			return
		var own: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i in own:
			indices.append(start + i)

	## The triangles of surface `surface` of `mesh`.
	static func triangles(mesh: Mesh, surface: int) -> int:
		var arrays := mesh.surface_get_arrays(surface)
		if arrays[Mesh.ARRAY_INDEX] != null:
			return (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3

	## Appends a unit box moved by `xform`; `uv` paints every face with one palette cell, or keeps
	## the box's own UVs when negative.
	func box(xform: Transform3D, uv: Vector2) -> void:
		var start := uvs.size()
		add(BoxMesh.new(), 0, xform)
		if uv.x >= 0.0:
			for i in range(start, uvs.size()):
				uvs[i] = uv

	func commit(material: Material) -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		if not vertices.is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(0, material)
		return mesh
