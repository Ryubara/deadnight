class_name HudPortrait
extends Control
## A small portrait of a player's Soldier as they wear it: the look's own parts and colours
## (`CharacterAssembler`, the assembler the wardrobe and the lot use), framed head and shoulders in
## a tiny 3D world of its own, drawn once into a texture and left alone (a portrait does not move,
## so it costs nothing after the first frame). The portrait is original art: the game's own model.
##
## `show_look` takes the look as plain data (`CharacterLook.to_dict`), so the HUD state can hold it
## and a client can send it. Tests that need no picture set `live` to false: the part keeps its
## place and its look, and builds no world.

## Pixels the portrait is drawn at, a little over its on-screen size so it stays crisp at 1440p.
const RENDER_SIZE := 160
const CAMERA_FOV := 22.0
## Head and shoulders: the camera looks at the face from slightly to the side, so the armband
## and the profile read.
const CAMERA_POSITION := Vector3(0.5, 1.62, 2.7)
const CAMERA_TARGET := Vector3(0.0, 1.5, 0.0)
## Frames the model stands before the picture is taken: its clip has to have posed it.
const POSE_FRAMES := 2
## A downed player's portrait is dimmed to this.
const DOWN_DIM := 0.35

## Whether a portrait builds its 3D world. A test with no use for the picture turns it off.
static var live := true

## The look and seat on show, as `"<seat>:<CharacterLook.key()>"`; "" before the first.
var look_key := ""
var seat := 0
var downed := false:
	set(value):
		downed = value
		_picture.modulate = Color.WHITE.darkened(1.0 - DOWN_DIM) if downed else Color.WHITE
## The model in the portrait's world, null when the portrait is not live.
var model: Node3D

var _tokens := UITokens.active()
var _viewport: SubViewport
var _picture := TextureRect.new()
var _wait := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	_picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_picture)
	_picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	# One picture, then nothing: wait for the idle clip to pose the model, render once, stop.
	if _viewport == null or _wait <= 0:
		return
	_wait -= 1
	if _wait == 0:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Shows the Soldier with `look_data` (a `CharacterLook.to_dict`; {} for the seat's own preset)
## wearing the armband of `new_seat`. Does nothing when it already shows that.
func show_look(look_data: Dictionary, new_seat: int) -> void:
	var look := (
		CharacterLook.from_dict(look_data)
		if not look_data.is_empty()
		else CharacterLook.from_preset(new_seat)
	)
	var key := "%d:%s" % [new_seat, look.key()]
	if key == look_key:
		return
	look_key = key
	seat = new_seat
	if not live:
		return
	if _viewport == null:
		_build_world()
	if model != null:
		model.queue_free()
	model = CharacterAssembler.assemble(look, new_seat)
	_viewport.add_child(model)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_wait = POSE_FRAMES


func _build_world() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(RENDER_SIZE, RENDER_SIZE)
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = _tokens.surface_raised
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.4, 0.35, 0.55)
	environment.ambient_light_energy = 0.8
	var world := WorldEnvironment.new()
	world.environment = environment
	_viewport.add_child(world)
	var camera := Camera3D.new()
	camera.fov = CAMERA_FOV
	_viewport.add_child(camera)
	camera.look_at_from_position(CAMERA_POSITION, CAMERA_TARGET)
	var key := SpotLight3D.new()
	key.light_color = _tokens.accent_bright
	key.light_energy = 6.0
	key.spot_range = 12.0
	key.spot_angle = 40.0
	_viewport.add_child(key)
	key.look_at_from_position(Vector3(1.4, 3.0, 3.0), Vector3(0.0, 1.5, 0.0))
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.45, 0.62, 1.0)
	rim.light_energy = 2.4
	rim.omni_range = 9.0
	rim.position = Vector3(-1.6, 2.2, -1.6)
	_viewport.add_child(rim)
	_picture.texture = _viewport.get_texture()
