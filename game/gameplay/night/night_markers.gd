class_name NightMarkers
extends Node
## Puts the night's world markers on the HUD from the camera the player looks through: the names
## over the other players' heads, and the next door to open (a diamond with its distance, pinned to
## the screen edge with an arrow when it is off screen). The HUD takes screen positions
## (`HudState.set_markers`) and never sees the world; this is the client side that projects.
##
## It runs every rendered frame, after the camera has moved (`process_priority`), and takes each
## drawn body where it is drawn this frame (`Node3D.get_global_transform_interpolated`), so a name
## stays on a head that is walking and on a camera that is turning.

## The name sits this far over a player's feet: the capsule's height and a little more.
const NAME_LIFT := 0.35
## The marker of a teammate on the ground floats this far over their feet, metres.
const DOWNED_LIFT := 0.9
## The kinds of marker the HUD draws.
const ALLY := &"ally"
const OBJECTIVE := &"objective"

## The node a player is drawn by (null when none is: the marker then goes to the frame's position).
var drawn: Callable = func(_player_id: int) -> Node3D: return null

var _hud_state: HudState
var _words: MapWords
var _state: ClientState
var _head := RemoteAvatars.PLAYER_TUNING.height + NAME_LIFT
## Every door of the lot and the points it is used from, the door that has to be open before it, and
## the doors that are open.
var _door_points: Dictionary[StringName, Array] = {}
var _door_requires: Dictionary[StringName, StringName] = {}
var _open: Dictionary[StringName, bool] = {}
var _last: Array[Dictionary] = []


func _init() -> void:
	# After every node that moves the camera (its rig places it in its own `_process`).
	process_priority = 1000


func setup(hud_state: HudState, state: ClientState, world: NightWorld, tuning: RulesTuning) -> void:
	_hud_state = hud_state
	_state = state
	_words = world.layout.words() if world.layout != null else null
	for door_id in world.door_ids():
		_door_points[door_id] = world.door_points(door_id)
		var item := tuning.economy.item(door_id)
		_door_requires[door_id] = item.requires if item != null else &""
	state.event_received.connect(_on_event)


## Doors already open when this client joined (the server's snapshot).
func load_doors(open_ids: Array) -> void:
	for door_id in open_ids:
		_open[StringName(door_id)] = true


## Where a point of the world is on the screen as a share of it, for a HUD part that follows one
## (a damage number); `Vector2.INF` when the point is behind the lens or there is no camera.
func screen_of(point: Vector3) -> Vector2:
	var camera := _camera()
	if camera == null:
		return Vector2.INF
	var found := MarkerProjection.project(camera, point)
	return Vector2.INF if found["behind"] else found["screen"]


## The markers this frame, in the HUD's form.
func markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var camera := _camera()
	if camera == null or not _state.has_frame():
		return out
	var here := _state.position()
	for id: int in _state.frame["players"]:
		if id != _state.player_id:
			out.append(_ally(camera, id, here))
	var marks: Dictionary = _state.frame.get("pings", {})
	for id: int in marks:
		out.append(_ping(camera, id, marks[id], here))
	var next := _next_door(here)
	for door_id in _door_points:
		if _is_next(door_id):
			out.append(_door(camera, door_id, here, door_id == next))
	return out


func _process(_delta: float) -> void:
	var list := markers()
	if list != _last:
		_last = list
		_hud_state.set_markers(list)


func _on_event(event: Dictionary) -> void:
	if event["type"] == &"door_opened":
		_open[StringName(event["door_id"])] = true


func _camera() -> Camera3D:
	return get_viewport().get_camera_3d() if is_inside_tree() else null


func _ally(camera: Camera3D, id: int, here: Vector3) -> Dictionary:
	var node: Node3D = drawn.call(id)
	var feet: Vector3 = _state.frame["players"][id]["pos"]
	if node != null:
		feet = node.get_global_transform_interpolated().origin
	var player: Dictionary = _state.frame["players"][id]
	var downed: bool = player.get("downed", false)
	# A downed body lies on the ground: its marker sits just over it, not over a standing head.
	var lift := _head if not downed else DOWNED_LIFT
	var found := MarkerProjection.project(camera, feet + Vector3(0.0, lift, 0.0))
	var marker := _marker(
		StringName("player_%d" % id),
		ALLY,
		found["screen"],
		here.distance_to(feet),
		str(_hud_state.team.get(id, {}).get("name", "")),
		downed and not player.get("dead", false)
	)
	# What the marker of a teammate on the ground says: the clock, and the hold on them if any. The
	# seconds are whole and the progress a hundredth, so a marker does not change on every tick.
	marker["downed"] = downed
	marker["dead"] = player.get("dead", false)
	marker["bleed"] = ceili(float(player.get("bleed", 0.0)))
	marker["revive"] = snappedf(float(player.get("revive", 0.0)), 0.01)
	# The level and icon beside the name (0 for none: a bot, no backend, or the viewer turned them
	# off).
	var shown := _hud_state.level_of(_hud_state.team.get(id, {}))
	marker["level"] = shown.x
	marker["icon"] = shown.y
	return marker


## A teammate's ping: a diamond over the spot, labelled with who put it up.
func _ping(camera: Camera3D, id: int, mark: Dictionary, here: Vector3) -> Dictionary:
	var at: Vector3 = mark["pos"]
	var found := MarkerProjection.project(camera, at + Vector3(0.0, 1.0, 0.0))
	var who := str(_hud_state.team.get(id, {}).get("name", "PING"))
	return _marker(
		StringName("ping_%d" % id), OBJECTIVE, found["screen"], here.distance_to(at), who, true
	)


func _door(camera: Camera3D, door_id: StringName, here: Vector3, important: bool) -> Dictionary:
	var at := _nearest_point(door_id, here)
	var found := MarkerProjection.project(camera, at)
	return _marker(
		door_id,
		OBJECTIVE,
		found["screen"],
		here.distance_to(at),
		NightHudBinding.door_name(door_id, _words),
		important
	)


func _marker(
	id: StringName, kind: StringName, screen: Vector2, distance: float, label: String, key: bool
) -> Dictionary:
	return {
		"id": id,
		"kind": kind,
		"x": screen.x,
		"y": screen.y,
		"distance": distance,
		"label": label,
		"important": key,
	}


## A closed door whose own door is open (or needs none): the doors the player can go to next.
func _is_next(door_id: StringName) -> bool:
	if _open.has(door_id):
		return false
	var needs: StringName = _door_requires.get(door_id, &"")
	return needs == &"" or _open.has(needs)


## The nearest of those doors: the one the pin and the arrow are for.
func _next_door(here: Vector3) -> StringName:
	var best := &""
	var best_distance := INF
	for door_id in _door_points:
		if _is_next(door_id):
			var distance := here.distance_to(_nearest_point(door_id, here))
			if distance < best_distance:
				best_distance = distance
				best = door_id
	return best


func _nearest_point(door_id: StringName, here: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var best_distance := INF
	for point: Vector3 in _door_points[door_id]:
		var distance := here.distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = point
	return best
