class_name NightScreen
extends UIScreen
## The night as a screen: the 3D night underneath, the HUD over it (`NightHudBinding` feeds it from
## the night's events), a pause menu on Esc and a result when the night is over. Both ways out
## lead back to the menu.
##
## Route to it with `UIRouter.push("res://ui/screens/night_screen.tscn")`; the main menu's Play
## does. To join a game server instead, set `join_url` first (the Join screen does): the screen
## takes it once and joins that night.

const PANEL_WIDTH := 520.0
const DIM := Color(0.0, 0.0, 0.0, 0.55)

## Whether the night warms up behind a loading screen before it starts. There is nothing to warm up
## without a renderer, so a headless run skips it.
static var warm_up_enabled := DisplayServer.get_name() != "headless"

## The server to join (`ws://host:port`) the next time this screen opens; empty plays alone.
static var join_url := ""
## With `join_url`: the autopilot plays this player (`--bot`), seen over its own shoulder.
static var join_as_bot := false
## A look to wear instead of the saved one (`--look`, for two windows of one machine that share a
## settings file); null wears the saved look.
static var own_look: CharacterLook

var night: Night

var _hud: Hud
var _loading: LoadingOverlay
var _touch: TouchControls
var _overlay: Control
var _title: UILabel
var _note: UILabel
var _resume: UIButton
var _quit: UIButton


## The look a `--look` value names: `N` is the preset N, `seed:N` a random look made from seed N.
static func look_from_flag(text: String) -> CharacterLook:
	if text.begins_with("seed:"):
		var rng := RandomNumberGenerator.new()
		rng.seed = text.trim_prefix("seed:").to_int()
		return CharacterLook.randomized(rng)
	return CharacterLook.from_preset(text.to_int())


func _ready() -> void:
	super._ready()
	# B (`ui_cancel`) crouches in the night: it must not take the player back to the menu.
	allow_back = false
	night = Night.new()
	night.warm_up = warm_up_enabled
	night.own_look = own_look
	night.challenge_board = ChallengeBoard.open()
	add_child(night)
	_hud = (load(Hud.SCENE) as PackedScene).instantiate()
	add_child(_hud)
	night.hud = _hud
	# Over the HUD, under the pause overlay; it shows only on a touch device (or when forced).
	_touch = TouchControls.new()
	_touch.state = _hud.state
	_touch.safe_insets_changed.connect(_on_safe_insets_changed)
	_touch.mirrored_changed.connect(_on_mirrored_changed)
	add_child(_touch)
	_build_overlay()
	night.night_over.connect(_on_night_over)
	if night.warm_up:
		_loading = LoadingOverlay.new()
		add_child(_loading)
		night.loading.connect(_loading.show_progress)
		night.ready_to_play.connect(_loading.finish)


## True while the touch controls are on screen and taking touches.
func touch_active() -> bool:
	return _touch != null and _touch.is_active()


func screen_enter() -> void:
	if join_url == "":
		await night.start(Night.Mode.HUMAN)
		return
	var url := join_url
	var mode := Night.Mode.AUTOPILOT if join_as_bot else Night.Mode.HUMAN
	night.shoulder_camera = join_as_bot
	join_url = ""
	join_as_bot = false
	_show_overlay("Joining", url, false)
	night.connect_failed.connect(_on_connect_failed)
	if await night.start_remote(url, mode):
		_overlay.hide()


func screen_pause() -> void:
	if night.running:
		_pause()


func screen_resume() -> void:
	pass


## The night is the backdrop; this screen paints none of its own.
func _draw() -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if night.state == null or night.state.over:
		return
	# Only `pause` (Esc, Start) pauses: `ui_cancel` is also B, which crouches. B resumes a paused
	# night, where it has nothing else to do.
	var resumes := night.is_paused() and event.is_action_pressed(&"ui_cancel")
	if event.is_action_pressed(&"pause") or resumes:
		if night.is_paused():
			_resume_night()
		else:
			_pause()
		get_viewport().set_input_as_handled()


## A left-handed layout swaps the HUD's corner columns with the buttons.
func _on_mirrored_changed(mirrored: bool) -> void:
	_hud.mirrored = mirrored


## The HUD keeps inside the notch and the rounded corners.
func _on_safe_insets_changed(insets: Vector4) -> void:
	_hud.offset_left = insets.x
	_hud.offset_top = insets.y
	_hud.offset_right = -insets.z
	_hud.offset_bottom = -insets.w


func _pause() -> void:
	night.set_paused(true)
	_show_overlay("Paused", "The dead wait.", true)


func _resume_night() -> void:
	_overlay.hide()
	_hud.reticle.set_shown(true)
	_touch.live = true
	night.set_paused(false)


func _on_connect_failed(reason: String) -> void:
	_show_overlay("Could not join", reason, false)


func _on_night_over(round_reached: int) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var points: int = night.state.points_earned
	_show_overlay(
		"You did not make it", "Round %d.  %d points earned." % [round_reached, points], false
	)


func _show_overlay(title: String, note: String, can_resume: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hud.reticle.set_shown(false)
	_touch.live = false
	_title.text = title
	_note.text = note
	_resume.visible = can_resume
	_overlay.show()
	(_resume if can_resume else _quit).grab_focus()


func _leave() -> void:
	UIRouter.pop()


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.hide()
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(centre)
	var panel := UIPanel.new()
	panel.variant = UIPanel.Variant.MARQUEE
	centre.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = PANEL_WIDTH
	box.add_theme_constant_override(&"separation", _tokens.space_md)
	panel.add_child(box)
	_title = _label(UILabel.Style.TITLE)
	_note = _label(UILabel.Style.BODY)
	box.add_child(_title)
	box.add_child(_note)
	_resume = _button("Resume", UIButton.Variant.PRIMARY)
	_resume.pressed.connect(_resume_night)
	_quit = _button("Back to the menu", UIButton.Variant.SECONDARY)
	_quit.pressed.connect(_leave)
	box.add_child(_resume)
	box.add_child(_quit)


func _label(style: UILabel.Style) -> UILabel:
	var label := UILabel.new()
	label.style = style
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _button(text: String, variant: UIButton.Variant) -> UIButton:
	var button := UIButton.new()
	button.text = text
	button.variant = variant
	return button
