extends Node
## A quiet stretch of the night for the beds alone: the lot at dusk with the crickets and the
## highway and nothing else (the rules paused in the intro: no round, no dead, no stings), so the
## crickets can be measured and heard in their own right against the highway. Run with Movie Maker
## (`--write-movie out.png --fixed-fps 10`), which writes the mix to `out.wav` beside the frames;
## `tools/audio/cricket_levels.py capture` reads it. Every sound that is played prints
## `SOUND <seconds into the movie> <id>`, which shows the stretch really was quiet (#781).

const VIEW_FROM := Vector3(-51.5, 3.2, -40.0)
const VIEW_AT := Vector3(-62.0, 1.3, -46.0)
## Movie Maker's frame rate (`--fixed-fps`), to turn a frame count into seconds.
const MOVIE_FPS := 10.0
## Long enough for the beds' three second fade-in and one whole 24 s loop of the crickets after it.
const SECONDS := 30.0

var _night: Night
var _bed: Label


func _ready() -> void:
	Audio.seed_random(781)
	Audio.connect(&"played", _on_played)
	var layer := CanvasLayer.new()
	add_child(layer)
	_bed = Label.new()
	_bed.position = Vector2(16.0, 12.0)
	_bed.add_theme_font_size_override("font_size", 28)
	_bed.add_theme_color_override("font_outline_color", Color.BLACK)
	_bed.add_theme_constant_override("outline_size", 6)
	layer.add_child(_bed)
	_night = Night.new()
	add_child(_night)
	await _night.start(Night.Mode.MANUAL)
	# The rules' clock stops, so the intro never ends and no round starts; the beds play on.
	_night.set_paused(true)
	var camera := Camera3D.new()
	camera.fov = 62.0
	add_child(camera)
	camera.make_current()
	camera.look_at_from_position(VIEW_FROM, VIEW_AT)
	for _i in int(SECONDS * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
	# Loops still playing when the engine shuts down are reported as leaked resources.
	Audio.stop_all()
	_night.queue_free()
	for _i in 3:
		await get_tree().physics_frame
	get_tree().quit()


func _process(_delta: float) -> void:
	_bed.text = (
		"%.1f s   crickets: trim %.1f dB   highway: trim %.1f dB"
		% [
			Engine.get_frames_drawn() / MOVIE_FPS,
			SoundCatalog.get_def(&"bed_crickets").volume_db,
			SoundCatalog.get_def(&"bed_highway").volume_db,
		]
	)


func _on_played(id: StringName, _position: Variant) -> void:
	print("SOUND %.2f %s" % [Engine.get_frames_drawn() / MOVIE_FPS, id])
