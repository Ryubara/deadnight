class_name ShotTaker
extends Node
## Saves a picture of the running view at each of `frames` (counted from when it was added), for a
## before and after of the same moment (`--fixed-fps 60` makes a frame a fixed step, so the same
## seed gives the same crowd at the same frame). Not part of the play: `BenchAblation` adds one for
## `shot=PATH` and `shot_frame=N,N`.

var path := ""
## The frames to take (`shot_frame=3300,3420`).
var frames: Array[int] = []
var _seen := 0


func _process(_delta: float) -> void:
	_seen += 1
	if _seen not in frames:
		return
	var image := get_viewport().get_texture().get_image()
	var file := path.replace(".png", "_%d.png" % _seen)
	image.save_png(file)
	print("SHOT ", file)
