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
## Seconds to wait for a game server to welcome us (a night may have to be built first).
const JOIN_SECONDS := 25.0

## Whether the night warms up behind a loading screen before it starts. There is nothing to warm up
## without a renderer, so a headless run skips it.
static var warm_up_enabled := DisplayServer.get_name() != "headless"

## The server to join (`ws://host:port`) the next time this screen opens; empty plays alone.
static var join_url := ""
## With `join_url`: the platform backend's ticket for the night, said in the hello (empty for a
## server with no backend, as on a developer's machine).
static var join_ticket := ""
## With `join_url`: the autopilot plays this player (`--bot`), seen over its own shoulder.
static var join_as_bot := false
## The match settings of the next local night (the Play screen sets them); taken once, the way
## `join_url` is. Joining a server ignores them: the server's are in its WELCOME.
static var match_settings: MatchSettings
## A look to wear instead of the saved one (`--look`, for two windows of one machine that share a
## settings file); null wears the saved look.
static var own_look: CharacterLook
## Where the player's challenges are kept; empty (tests, captures) counts nothing and writes
## nothing. The game's root sets it, so only the real game keeps a save.
static var challenge_path := ""

## How a night played alone starts, for a run that is not a person's (`KillBench`): the bot plays,
## filmed from its shoulder, under this tuning (the defaults when null).
static var start_mode := Night.Mode.HUMAN
static var start_tuning: RulesTuning = null
static var shoulder_camera := false

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
	night.touch_active = touch_active
	night.own_look = own_look
	if match_settings != null and join_url == "":
		night.match_settings = match_settings
	match_settings = null
	if challenge_path != "":
		night.challenge_board = ChallengeBoard.open(challenge_path)
	add_child(night)
	_hud = (load(Hud.SCENE) as PackedScene).instantiate()
	add_child(_hud)
	night.hud = _hud
	# Over the HUD, under the pause overlay; it shows only on a touch device (or when forced).
	_touch = TouchControls.new()
	_touch.state = _hud.state
	_touch.safe_insets_changed.connect(_on_safe_insets_changed)
	_touch.mirrored_changed.connect(_on_mirrored_changed)
	_touch.look_gain = _look_gain
	add_child(_touch)
	_build_overlay()
	night.night_over.connect(_on_night_over)
	night.ready_to_play.connect(_watch_mouse)
	if night.warm_up:
		_loading = LoadingOverlay.new()
		add_child(_loading)
		night.loading.connect(_loading.show_progress)
		night.ready_to_play.connect(_loading.finish)
	_start_if_run_alone.call_deferred()


## Run on its own (F6 in the editor, or as the main scene) no router enters the screen, so it
## starts the night itself: a solo night, as the menu's Play does. Inside the router, or a test,
## `screen_enter` comes from there.
func _start_if_run_alone() -> void:
	if get_tree().current_scene == self and not night.running:
		screen_enter()


## True while the touch controls are on screen and taking touches.
func touch_active() -> bool:
	return _touch != null and _touch.is_active()


## True while the centre reticle is on screen (a browser test reads it, #517).
func reticle_shown() -> bool:
	return _hud != null and _hud.reticle.is_visible_in_tree()


func screen_enter() -> void:
	if join_url == "":
		night.shoulder_camera = shoulder_camera
		await night.start(start_mode, Night.SEED, start_tuning)
		return
	var url := join_url
	var mode := Night.Mode.AUTOPILOT if join_as_bot else Night.Mode.HUMAN
	night.shoulder_camera = join_as_bot
	var link := WebSocketLink.new()
	link.ticket = join_ticket
	join_url = ""
	join_ticket = ""
	join_as_bot = false
	_show_overlay("Joining", "" if link.ticket != "" else url, false)
	night.connect_failed.connect(_on_connect_failed)
	if await night.start_remote(url, mode, JOIN_SECONDS, link):
		_hide_overlay()


func screen_pause() -> void:
	if night.running:
		_pause()


## A live night takes its keys itself: Start is `pause` and also `ui_accept`, and the router would
## spend it on giving a menu its focus (#494). Only the overlay's buttons are navigated.
func wants_focus_key() -> bool:
	return _overlay.visible


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


## The factor on a touch look drag: the aim assist slows it near a zombie.
func _look_gain() -> float:
	return night.assist.friction() if night != null and night.assist != null else 1.0


## A left-handed layout swaps the HUD's corner columns with the buttons.
func _on_mirrored_changed(mirrored: bool) -> void:
	_hud.mirrored = mirrored


## The HUD keeps inside the notch and the rounded corners.
func _on_safe_insets_changed(insets: Vector4) -> void:
	_hud.offset_left = insets.x
	_hud.offset_top = insets.y
	_hud.offset_right = -insets.z
	_hud.offset_bottom = -insets.w


## The player's body takes the mouse back from the platform (a browser's first Esc, a window that
## lost focus) without a `pause` key press: the menu opens in the same frame, as Esc would.
func _watch_mouse() -> void:
	var body := night.player()
	if night.mode == Night.Mode.HUMAN and body != null:
		body.grip_lost.connect(_on_mouse_lost)


func _on_mouse_lost() -> void:
	if night.state != null and not night.state.over and not night.is_paused():
		_pause()


func _pause() -> void:
	night.set_paused(true)
	_show_overlay("Paused", "The dead wait.", true)


func _resume_night() -> void:
	_hide_overlay()
	night.set_paused(false)


## Takes the card away and gives the night back what `_show_overlay` took: the reticle, the
## scoreboard on Tab and the touch controls. Every way the card goes (Resume, a joined night
## starting) comes here: a night joined online once ran with none of them until a pause and a Resume
## (#517).
func _hide_overlay() -> void:
	_overlay.hide()
	_hud.reticle.set_shown(true)
	_hud.scoreboard_enabled = true
	_touch.live = true


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
	_hud.scoreboard_enabled = false
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
