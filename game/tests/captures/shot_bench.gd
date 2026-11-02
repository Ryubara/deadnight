extends Node
## Where a shot lands against the reticle, in a browser (#601): the game's own night screen with the
## touch layer on and a phone's safe area given by the page's query, a wall put square across the
## reticle at the distance the page asks for (`window.__shotWant = {seq, metres}`), and what the
## page needs to fire with real touches: where the Fire and Aim buttons are. Every shot the real
## touch makes is measured by `ShotRig` and published in `window.__shot.results`. Not part of the
## game: `tools/web_smoke/shot_on_crosshair.py` exports a copy of the project that starts on this
## scene. The query: `?insets=59,0,59,21` (the page's CSS pixels: left, top, right, bottom).

const MENU := "res://ui/screens/main_menu.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"
## The ground the wall may stand on: the farthest wall asked for, and a margin.
const OPEN_METRES := 28.0
const PUBLISH_EVERY := 0.05
## How far (m) the drawn plate stands in front of the wall's face, so marks are not inside it.
const WALL_FRONT := 0.12

var _rig: ShotRig
var _controls: TouchControls
var _since := 0.0
var _seen_seq := 0
var _ready_seq := 0
var _wall_settle := 0
var _marked := 0
var _metres := 1.0


func _ready() -> void:
	_run.call_deferred()


func _process(delta: float) -> void:
	if _rig == null:
		return
	_since += delta
	if _since < PUBLISH_EVERY:
		return
	_since = 0.0
	_take_orders()
	_publish()


func _physics_process(_delta: float) -> void:
	# A wall joins the physics space a physics frame after it is made.
	if _wall_settle > 0:
		_wall_settle -= 1
		if _wall_settle == 0:
			_ready_seq = _seen_seq


func _run() -> void:
	await get_tree().process_frame
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	await screen.night.ready_to_play
	_controls = screen.find_children("*", "TouchControls", true, false)[0] as TouchControls
	_rig = ShotRig.attach(self, screen, true)
	_rig.spread_off()
	var insets := _insets_of(_query().get("insets", "0,0,0,0"))
	if insets != Vector4.ZERO:
		_rig.safe_area(insets)
	# The lot's bodies join the physics space on the frames after the night is ready.
	for _i in 900:
		await get_tree().physics_frame
		if (
			_rig.night.server.tick_count >= 10
			and _rig.night.player().global_position != Vector3.ZERO
		):
			break
	if not _rig.face_open_ground(OPEN_METRES):
		var at := _rig.night.player().global_position
		var why := (
			"no open ground in the lot: player at "
			+ str(at)
			+ ", ticks "
			+ str(_rig.night.server.tick_count)
		)
		why += ", running " + str(_rig.night.running) + ", paused " + str(_rig.night.is_paused())
		_eval("window.__shot = " + JSON.stringify({"failed": why}) + ";")
		return
	_publish()


## The page's CSS pixels in canvas units: the safe area in the page's own units is what the browser
## reports, and the touch layer scales it by the canvas width over the page width.
func _insets_of(text: String) -> Vector4:
	var parts := text.split(",")
	if parts.size() != 4:
		return Vector4.ZERO
	var page_width := float(_eval_value("window.innerWidth"))
	var k := get_viewport().get_visible_rect().size.x / maxf(page_width, 1.0)
	return Vector4(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3])) * k


## The wall the page asked for (a new `seq`), put across the reticle.
func _take_orders() -> void:
	var raw: Variant = _eval_value("JSON.stringify(window.__shotWant || null)")
	if not raw is String:
		return
	var want: Variant = JSON.parse_string(raw)
	if not want is Dictionary or int(want.get("seq", 0)) == _seen_seq:
		return
	_seen_seq = int(want["seq"])
	_metres = float(want["metres"])
	var dot := _rig.wall_at(_metres)
	_draw_target(_rig.last_wall(), dot)
	_marked = _rig.results.size()
	_wall_settle = 3


## What a capture shows: a plate on the wall, a green mark where the reticle points and, after each
## shot, a red mark where it landed. The two are one mark when the shot goes where the reticle is.
func _draw_target(wall: StaticBody3D, dot: Vector3) -> void:
	var plate := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * _metres * 0.6
	plate.mesh = quad
	plate.material_override = _flat(Color(0.82, 0.8, 0.74))
	wall.add_child(plate)
	plate.position = Vector3(0.0, 0.0, WALL_FRONT)
	_mark(wall, dot, Color(0.1, 0.95, 0.3), 0.03, WALL_FRONT * 2.0)


func _mark(wall: StaticBody3D, point: Vector3, colour: Color, share: float, lift: float) -> void:
	var mark := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = share * _metres
	ball.height = ball.radius * 2.0
	mark.mesh = ball
	mark.material_override = _flat(colour)
	wall.add_child(mark)
	mark.global_position = point
	mark.position.z = lift


func _flat(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = colour
	return material


func _publish() -> void:
	var wall := _rig.last_wall()
	while wall != null and _marked < _rig.results.size():
		var end: Vector3 = _rig.results[_marked]["end"]
		_mark(wall, end, Color(0.95, 0.1, 0.1), 0.012, WALL_FRONT * 3.0)
		_marked += 1
	var results: Array = []
	for result in _rig.results:
		(
			results
			. append(
				{
					"off": snappedf(result["off"], 0.001),
					"degrees": snappedf(result["degrees"], 0.0001),
					"drift": snappedf(result["drift"], 0.0001),
					"end": [result["end"].x, result["end"].y, result["end"].z],
				}
			)
		)
	var canvas := get_viewport().get_visible_rect().size
	var data := {
		"ready": _ready_seq,
		"fire": _to_page(_controls.button_circle(TouchLayout.FIRE)["centre"]),
		"aim": _to_page(_controls.button_circle(TouchLayout.AIM)["centre"]),
		"reticle": _to_page(_rig.reticle_centre()),
		"canvas": [canvas.x, canvas.y],
		"insets": [_controls.insets.x, _controls.insets.y, _controls.insets.z, _controls.insets.w],
		"paused": _rig.night.is_paused(),
		"results": results,
	}
	_eval("window.__shot = %s;" % JSON.stringify(data))


func _to_page(point: Vector2) -> Array:
	var window := get_viewport().get_final_transform() * point
	var ratio := maxf(float(_eval_value("window.devicePixelRatio")), 1.0)
	return [window.x / ratio, window.y / ratio]


func _eval_value(script: String) -> Variant:
	return JavaScriptBridge.eval(script, true) if OS.has_feature("web") else null


func _eval(script: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(script)
	else:
		print("SHOT ", script)


## The page's query as `{name: value}`.
func _query() -> Dictionary:
	var parsed := {}
	if not OS.has_feature("web"):
		return parsed
	var search: Variant = JavaScriptBridge.eval("window.location.search", true)
	for pair in String(search).trim_prefix("?").split("&"):
		var parts := pair.split("=", true, 1)
		if parts.size() == 2:
			parsed[parts[0]] = parts[1]
	return parsed
