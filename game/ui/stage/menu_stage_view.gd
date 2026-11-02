class_name MenuStageView
extends SubViewportContainer
## The menu's stage as a control: a full-screen picture of `MenuStage`, drawn in a viewport of its
## own so it can be drawn smaller, or only once.
##
## Three levels (`StageGovernor.Level`): live, live at half resolution, and a still (the stage is
## drawn once on every change and then left alone). The setting `video/menu_scene` fixes one; on
## "auto" the governor steps down when frames run long. Reduced motion cuts the camera and stops
## the dead.

## Emitted when the level changes.
signal level_changed(level: StageGovernor.Level)

## Setting values of `video/menu_scene`.
const MODE_AUTO := 0
const MODE_LIVE := 1
const MODE_STILL := 2

var stage := MenuStage.new()
var governor := StageGovernor.new()
## A test or a capture steps the stage itself with `advance`.
var manual := false
var level := StageGovernor.Level.LIVE
## A mode that overrides the setting for this view (a run's own choice); -1 follows the setting.
var forced_mode := -1

var _viewport := SubViewport.new()
var _mode := MODE_AUTO
var _active := true
var _tab := MenuTab.Id.PLAY


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.handle_input_locally = false
	_viewport.gui_disable_input = true
	_viewport.size = Vector2i(1920, 1080)
	add_child(_viewport)
	_viewport.add_child(stage)


func _ready() -> void:
	resized.connect(_follow_size)
	UIMotion.changed().connect(_follow_motion)
	Settings.changed.connect(_on_setting)
	_mode = _wanted_mode()
	stage.build()
	stage.show_look(LookStore.load_look(), MenuHero.saved_weapon())
	_follow_motion(UIMotion.reduced)
	_follow_size()
	_apply_mode()
	stage.advance(0.0)
	refresh()


func _exit_tree() -> void:
	if Settings.changed.is_connected(_on_setting):
		Settings.changed.disconnect(_on_setting)


func _process(delta: float) -> void:
	if manual or not _active or level == StageGovernor.Level.STILL:
		return
	stage.advance(delta)
	# Movie Maker and tests run at a fixed rate that says nothing about the machine.
	if _mode == MODE_AUTO and not OS.has_feature("movie") and governor.feed(delta):
		set_level(governor.level)


## Turns the camera to a tab (a cut in a still).
func show_tab(tab: MenuTab.Id) -> void:
	_tab = tab
	stage.show_tab(tab, level == StageGovernor.Level.STILL)
	if level == StageGovernor.Level.STILL:
		stage.advance(0.0)
		refresh()


## Dresses the soldier again from the save (the wardrobe saved a new look, or a weapon was chosen).
func reload_look() -> void:
	stage.show_look(LookStore.load_look(), MenuHero.saved_weapon())
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
			governor.level = StageGovernor.Level.LIVE
			set_level(StageGovernor.Level.LIVE)
	_apply_level()


func _apply_level() -> void:
	stretch_shrink = 2 if level == StageGovernor.Level.HALF else 1
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


func _follow_motion(reduced: bool) -> void:
	stage.rig.set_reduced(reduced)
	stage.animated = not reduced and level != StageGovernor.Level.STILL


func _on_setting(key: StringName, _value: Variant) -> void:
	if key == SettingsService.MENU_SCENE:
		_mode = _wanted_mode()
		_apply_mode()
	elif key == SettingsService.SHOWCASE_WEAPON or key == SettingsService.CHARACTER_LOOK:
		reload_look()
