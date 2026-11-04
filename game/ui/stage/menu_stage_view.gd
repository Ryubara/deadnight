class_name MenuStageView
extends Control
## The menu's stage as a control: a full-screen picture of `MenuStage`, drawn in a viewport of its
## own so it can be drawn smaller, or only once.
##
## Three levels (`StageGovernor.Level`): live, live at half resolution, and a still (the stage is
## drawn once on every change and then left alone). The setting `video/menu_scene` fixes one; on
## "auto" the governor steps down when frames run long, and back up when they recover. Reduced
## motion cuts the camera and stops the dead.
##
## The viewport is drawn at the window's own pixels (`render_size`), not at the control's size in
## the project's 1920 x 1080 canvas: under the canvas stretch a 2560 x 1440 window has a control of
## 1920 x 1080, and a viewport of that size was stretched by a third (soft, stair-stepped edges).
## A `SubViewportContainer` cannot do that (with `stretch` on it owns the viewport's size; off, it
## grows to the viewport's), so the picture is a `TextureRect` of the viewport's texture.

## Emitted when the level changes.
signal level_changed(level: StageGovernor.Level)

## The anti-aliasing of the stage: the project setting `msaa_3d` does not reach a SubViewport.
## The HUD portrait and the look preview use the same 4x.
const MSAA := Viewport.MSAA_4X
## The tallest the stage is drawn, in pixels: a 4K window draws it at 1440p and the display
## stretches it the rest of the way (the multisample buffer at 4K is what a weak GPU cannot hold).
const MAX_RENDER_HEIGHT := 1440

## Setting values of `video/menu_scene`.
const MODE_AUTO := 0
const MODE_LIVE := 1
const MODE_STILL := 2

var stage := MenuStage.new()
var governor := StageGovernor.new()
## A test or a capture steps the stage itself with `advance`.
var manual := false
## What the soldier on the stage may wear (the account's level); the profile file's when unset.
var unlocks: LookUnlocks = null
var level := StageGovernor.Level.LIVE
## A mode that overrides the setting for this view (a run's own choice); -1 follows the setting.
var forced_mode := -1
## The graphics adapter's name, as the engine reports it (a test sets another).
var adapter_name := detect_adapter()

var _viewport := SubViewport.new()
var _picture := TextureRect.new()
var _mode := MODE_AUTO
var _active := true
var _tab := MenuTab.Id.PLAY


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport.own_world_3d = true
	_viewport.msaa_3d = MSAA
	_viewport.handle_input_locally = false
	_viewport.gui_disable_input = true
	_viewport.size = Vector2i(1920, 1080)
	add_child(_viewport)
	_picture.texture = _viewport.get_texture()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_picture)
	_viewport.add_child(stage)


## The graphics adapter's name. A browser hides it from the engine ("WebKit WebGL"), so on the web
## the unmasked renderer the browser tells a page is added: that is where "SwiftShader" shows.
static func detect_adapter() -> String:
	var name := RenderingServer.get_video_adapter_name()
	if OS.has_feature("web"):
		var script := (
			"(function(){var c=document.createElement('canvas');"
			+ "var g=c.getContext('webgl2')||c.getContext('webgl');if(!g){return '';}"
			+ "var e=g.getExtension('WEBGL_debug_renderer_info');"
			+ "return e?String(g.getParameter(e.UNMASKED_RENDERER_WEBGL)):'';})()"
		)
		name += " " + str(JavaScriptBridge.eval(script, true))
	return name


func _ready() -> void:
	resized.connect(_follow_size)
	# The window can change its pixels without changing the control (the same aspect), and
	# `_enter_tree` follows that.
	resized.connect(_fit_viewport)
	UIMotion.changed().connect(_follow_motion)
	Settings.changed.connect(_on_setting)
	_mode = _wanted_mode()
	stage.build()
	stage.show_look(LookStore.load_look(unlocks), MenuHero.saved_weapon())
	_follow_motion(UIMotion.reduced)
	_follow_size()
	_apply_mode()
	stage.advance(0.0)
	refresh()
	_fit_viewport()


func _enter_tree() -> void:
	if not get_tree().root.size_changed.is_connected(_fit_viewport):
		get_tree().root.size_changed.connect(_fit_viewport)


func _exit_tree() -> void:
	if get_tree().root.size_changed.is_connected(_fit_viewport):
		get_tree().root.size_changed.disconnect(_fit_viewport)
	if Settings.changed.is_connected(_on_setting):
		Settings.changed.disconnect(_on_setting)


func _process(delta: float) -> void:
	if manual or not _active or level == StageGovernor.Level.STILL:
		return
	stage.advance(delta)
	# Movie Maker and tests run at a fixed rate that says nothing about the machine.
	if _mode == MODE_AUTO and not OS.has_feature("movie") and governor.feed(delta):
		set_level(governor.level)


## Tells the camera the window is a phone's (poses leave room for wider panels).
func set_compact(compact: bool) -> void:
	stage.rig.compact = compact


## Turns the camera to a tab (a cut in a still).
func show_tab(tab: MenuTab.Id) -> void:
	_tab = tab
	stage.show_tab(tab, level == StageGovernor.Level.STILL)
	if level == StageGovernor.Level.STILL:
		stage.advance(0.0)
		refresh()


## Dresses the soldier again from the save (the wardrobe saved a new look, or a weapon was chosen).
func reload_look() -> void:
	stage.show_look(LookStore.load_look(unlocks), MenuHero.saved_weapon())
	refresh()


## Shows a look that is not saved yet (the wardrobe's working copy) with `weapon`, or the saved
## weapon when none is given.
func preview_look(look: CharacterLook, weapon := &"") -> void:
	stage.show_look(look, weapon if weapon != &"" else MenuHero.saved_weapon())
	refresh()


## Turns the soldier by hand, in radians.
func turn(radians: float) -> void:
	stage.hero_turn += radians
	if level == StageGovernor.Level.STILL:
		stage.advance(0.0)
		refresh()


## Draws nothing while another screen covers the menu.
func set_active(active: bool) -> void:
	_active = active
	_viewport.render_target_update_mode = _update_mode()


func set_level(to: StageGovernor.Level) -> void:
	if to == level:
		return
	level = to
	_apply_level()
	level_changed.emit(level)


## Draws the stage once more (a still redraws only when asked).
func refresh() -> void:
	if level == StageGovernor.Level.STILL and _active:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func viewport() -> SubViewport:
	return _viewport


## How many pixels the stage is drawn in: the control's size times the canvas scale the window
## puts on it (so one pixel of the stage is one pixel of the screen), at most `MAX_RENDER_HEIGHT`
## tall, divided by two at half resolution.
func render_size() -> Vector2i:
	var scale_px := 1.0
	if is_inside_tree():
		scale_px = get_viewport().get_final_transform().get_scale().y
	return render_size_for(size, scale_px, level == StageGovernor.Level.HALF)


static func render_size_for(control_size: Vector2, canvas_scale: float, half: bool) -> Vector2i:
	var pixels := control_size * canvas_scale
	if pixels.y > MAX_RENDER_HEIGHT:
		pixels *= MAX_RENDER_HEIGHT / pixels.y
	if half:
		pixels *= 0.5
	return Vector2i(maxi(roundi(pixels.x), 1), maxi(roundi(pixels.y), 1))


func _wanted_mode() -> int:
	if forced_mode >= 0:
		return forced_mode
	return int(Settings.get_value(SettingsService.MENU_SCENE))


func _apply_mode() -> void:
	match _mode:
		MODE_STILL:
			governor.level = StageGovernor.Level.STILL
			set_level(StageGovernor.Level.STILL)
		_:
			# On a renderer that draws on the CPU the stage would hold the menu to a few frames a
			# second for the seconds the governor needs to notice: start on the still.
			var start := StageGovernor.Level.LIVE
			if _mode == MODE_AUTO and StageGovernor.is_software(adapter_name):
				start = StageGovernor.Level.STILL
			governor.level = start
			set_level(start)
	_apply_level()


func _apply_level() -> void:
	_fit_viewport()
	stage.animated = level != StageGovernor.Level.STILL and not UIMotion.reduced
	if level == StageGovernor.Level.STILL:
		stage.show_tab(_tab, true)
		stage.advance(0.0)
	_viewport.render_target_update_mode = _update_mode()
	refresh()


func _update_mode() -> SubViewport.UpdateMode:
	if not _active:
		return SubViewport.UPDATE_DISABLED
	return (
		SubViewport.UPDATE_ONCE if level == StageGovernor.Level.STILL else SubViewport.UPDATE_ALWAYS
	)


func _follow_size() -> void:
	if size.y > 0.0:
		stage.rig.set_aspect(size.x / size.y)
		if level == StageGovernor.Level.STILL:
			stage.show_tab(_tab, true)
			stage.advance(0.0)
			refresh()


func _fit_viewport() -> void:
	if size.x > 0.0 and size.y > 0.0:
		_viewport.size = render_size()


func _follow_motion(reduced: bool) -> void:
	stage.rig.set_reduced(reduced)
	stage.animated = not reduced and level != StageGovernor.Level.STILL


func _on_setting(key: StringName, _value: Variant) -> void:
	if key == SettingsService.MENU_SCENE:
		_mode = _wanted_mode()
		_apply_mode()
	elif key == SettingsService.SHOWCASE_WEAPON or key == SettingsService.CHARACTER_LOOK:
		reload_look()
