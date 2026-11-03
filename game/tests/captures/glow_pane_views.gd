extends Node3D
## A lit window of the drive-in's concession seen from outside and from inside (issue #701): the
## pane must glow from the field and read as lit glass from the room, not as a hole. Not part of
## the game. Run with Movie Maker; arguments after `--`: `--view=out|in|beside|wall` (a camera on
## the field side, one in the room, one low and to the side to see the pane edge on, one in the
## room facing the wall the neon sign hangs outside),
## `--window=WindowW|WindowE`.

const GREYBOX := "res://world/drive_in_greybox.tscn"
const SETTLE_FRAMES := 6
## Camera places: where it stands (the pane is at x -6, y 1.7, z -4.05 in the north wall).
const VIEWS := {
	"out": Vector3(-6.0, 1.6, -9.0),
	"in": Vector3(-6.0, 1.6, -0.5),
	"beside": Vector3(-9.0, 1.2, -7.0),
	# In the room facing the north wall's door, where the neon sign hangs outside: its halo must not
	# show through the wall.
	"wall": Vector3(-1.0, 1.6, -0.5),
}
## Where each view looks (the pane's place unless named here).
const TARGETS := {"wall": Vector3(0.0, 3.0, -4.0)}

var _frames := 0


func _ready() -> void:
	var args := _parse_args()
	var lot := (load(GREYBOX) as PackedScene).instantiate() as Node3D
	add_child(lot)
	var pane := lot.get_node("Concession/Lamps/%s" % args.get("window", "WindowW")) as Node3D
	var camera := Camera3D.new()
	camera.fov = 70.0
	camera.current = true
	add_child(camera)
	var from: Vector3 = VIEWS[args.get("view", "out")]
	if pane.global_position.x > 0.0:
		from.x = -from.x
	camera.global_position = from
	camera.look_at(TARGETS.get(args.get("view", "out"), pane.global_position), Vector3.UP)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == SETTLE_FRAMES:
		print("GLOW_PANE settled")


func _parse_args() -> Dictionary:
	var parsed := {}
	for argument in OS.get_cmdline_user_args():
		var parts := argument.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else "1"
	return parsed
