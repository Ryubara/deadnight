extends Node3D
## Places the camera for a greybox capture. Pick the view with a user argument after `--`:
## `-- --view=top|night_top|start|concession|concession_in|booth|yard|backlot|plaza|road`, and the
## props' views `yard_drums|yard_east|backlot_rows|road_block|alley|midway_court|field_west|`
## `field_east|screen_apron|road_west`.
## Not used in the game.
##
## Third-person views (`--view=tp:<CameraProbes marker>`) put the camera where the player's shoulder
## camera would be, with a capsule for the player. Options: `--offset=<m along the passage>`,
## `--turn=<degrees>` (180 walks the other way), `--side=1|-1` (the shoulder), `--y=<feet height>`,
## `--doors=closed` (default open), `--flood`.

## Camera spots for the player-height views: position, then the point looked at (metres).
const VIEWS := {
	"start": [Vector3(0, 1.7, -12), Vector3(0, 6.0, -48)],
	"concession": [Vector3(0, 1.7, -20), Vector3(0, 2.0, -4)],
	"concession_in": [Vector3(0, 1.7, 6.5), Vector3(0, 1.6, -3)],
	"booth": [Vector3(0, 5.6, 24.5), Vector3(0, 3.5, -30)],
	"yard": [Vector3(22, 1.7, 13), Vector3(40, 1.4, 18)],
	"backlot": [Vector3(-20, 1.7, 34), Vector3(-46, 2.0, 12)],
	"road": [Vector3(8, 1.7, 56), Vector3(-34, 1.2, 57)],
	"plaza": [Vector3(0, 1.7, 58), Vector3(0, 2.5, 40)],
	# The props (tools/world/lot_props.py), at the player's eye height.
	"yard_drums": [Vector3(25, 1.7, 15), Vector3(23, 0.8, 4)],
	"yard_east": [Vector3(45, 1.7, 21), Vector3(56, 1.0, 24)],
	"backlot_rows": [Vector3(-19, 1.7, 9), Vector3(-45, 1.0, 13)],
	"road_block": [Vector3(38, 1.7, 55), Vector3(54, 1.0, 56)],
	"alley": [Vector3(-12.5, 1.7, 6), Vector3(-13.5, 0.8, -3)],
	"midway_court": [Vector3(14, 1.7, 17), Vector3(9, 1.0, 29)],
	"field_west": [Vector3(-42, 1.7, -18), Vector3(-60, 1.0, -30)],
	"field_east": [Vector3(46, 1.7, -16), Vector3(60, 1.0, -34)],
	"screen_apron": [Vector3(30, 1.7, -40), Vector3(48, 1.0, -51)],
	"road_west": [Vector3(-30, 1.7, 54), Vector3(-58, 1.0, 57)],
}
const TOP_SIZE := 128.0  # orthographic size (the vertical extent in metres) of the whole-lot view
const TOP_CENTRE := Vector3(0, 0, 6)

@onready var _lighting: Node3D = $DriveInGreybox/Lighting


func _ready() -> void:
	var view := _view_from_args()
	var camera := $Camera3D as Camera3D
	if view == "top" or view == "night_top":
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = TOP_SIZE
		camera.look_at_from_position(TOP_CENTRE + Vector3(0, 100, 0), TOP_CENTRE, Vector3(0, 0, -1))
		_set_labels_visible(true)
		if view == "top":
			_flood_light()
	elif view.begins_with("tp:"):
		_third_person(view.trim_prefix("tp:"), camera)
	elif VIEWS.has(view):
		camera.fov = 80.0
		camera.look_at_from_position(VIEWS[view][0], VIEWS[view][1])
	else:
		push_error("unknown view '%s'" % view)


func _third_person(probe_name: String, camera: Camera3D) -> void:
	if _arg("doors", "open") != "closed":
		$DriveInGreybox/Doors.queue_free()
	if _arg("flood", "") != "":
		_flood_light()
	camera.fov = 75.0
	camera.near = 0.05
	# The collision of the CSG boxes is not in the physics world until a few ticks in.
	for i in 4:
		await get_tree().physics_frame
	var marker := $DriveInGreybox/CameraProbes.get_node(probe_name) as Marker3D
	var yaw := marker.global_transform.basis.get_euler().y + deg_to_rad(float(_arg("turn", "0")))
	var feet := marker.global_position - Basis(Vector3.UP, yaw).z * float(_arg("offset", "0"))
	feet.y = float(_arg("y", str(marker.global_position.y)))
	var rig := CameraProbe.rig(
		get_world_3d().direct_space_state, feet, yaw, float(_arg("side", "1"))
	)
	camera.global_transform = Transform3D(Basis(Vector3.UP, yaw), rig["camera"])
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = CameraProbe.body_radius()
	capsule.height = CameraProbe.body_height()
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.95, 0.55, 0.15)
	capsule.material = paint
	body.mesh = capsule
	body.position = feet + Vector3(0.0, CameraProbe.body_height() / 2.0, 0.0)
	add_child(body)
	print("camera: arm %.2f m, free %s" % [rig["arm"], rig["free"]])


func _arg(key: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg == "--" + key:
			return "1"
		if arg.begins_with("--%s=" % key):
			return arg.trim_prefix("--%s=" % key)
	return fallback


func _view_from_args() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--view="):
			return arg.trim_prefix("--view=")
	return "start"


func _set_labels_visible(on: bool) -> void:
	for label in get_tree().get_nodes_in_group("area_labels"):
		label.visible = on


## The plan view is lit evenly so the colours read; the night view keeps the real lights.
func _flood_light() -> void:
	var env := ($DriveInGreybox/Lighting/WorldEnvironment as WorldEnvironment).environment
	env.ambient_light_energy = 2.2
	env.fog_enabled = false  # from 100 m up the night's fog hides the plan
	var moon := _lighting.get_node("Moon") as DirectionalLight3D
	moon.light_energy = 1.0
	for light in get_tree().get_nodes_in_group("powered_light"):
		light.visible = false
