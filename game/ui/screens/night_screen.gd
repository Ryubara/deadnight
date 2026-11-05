class_name NightScreen
extends UIScreen
## The night as a screen: the 3D night underneath, the HUD over it (`NightHudBinding` feeds it
## from the night's events), the night's menu and, when the night is over, the end sequence: the
## camera flies over the map (`EndCamera`), the board shows every player's numbers over it
## (`HudEndBoard`), the server's intermission clock counts down, and at its end the player is back
## where the night was made: the lobby they came from online (the same lobby, reopened by the
## backend), their Play screen alone. The menu's Leave night and the board's Leave go back at once
## (`docs/design/end-of-night.md`).
##
## The menu opens on Esc, the pad's Start or the touch layer's pause button (or when the platform
## takes the mouse back). It has Resume, Settings (the same screen as the main menu's, held inside
## this one: a router push would switch the night off, and a night played with others goes on) and
## Leave night. Played alone the night stands still behind it; played with others it keeps running
## and only this player's controls are off.
##
## Route to it with `UIRouter.push("res://ui/screens/night_screen.tscn")`; the Play screen (the
## menu's Solo) does, after it sets `match_settings`. To join a game server instead, set `join_url`
## first (the Join screen does): the screen takes it once and joins that night.

const PANEL_WIDTH := 520.0
const DIM := Color(0.0, 0.0, 0.0, 0.55)
## Seconds to wait for a game server to welcome us (a night may have to be built first).
const JOIN_SECONDS := 25.0
const SETTINGS_SCENE := "res://ui/screens/settings_screen.tscn"
## How many times (every `RETURN_WAIT` seconds) the lobby is asked for after the night closed,
## until the backend has opened it again; then the player is sent back to the screen the night
## came from.
const RETURN_TRIES := 20
const RETURN_WAIT := 0.5
## What the board's clock says it counts to, and the words of its way out.
const CAPTION_ONLINE := "BACK TO THE LOBBY IN"
const CAPTION_ALONE := "BACK TO SETUP IN"
const LEAVE_ONLINE := "Leave"
const LEAVE_ALONE := "Back"
const OPENING := "OPENING THE LOBBY"

## Whether the night warms up behind a loading screen before it starts. There is nothing to warm up
## without a renderer, so a headless run skips it.
static var warm_up_enabled := DisplayServer.get_name() != "headless"
## Whether a person's night opens with the helicopter drop (#1057, `ArrivalCutscene`). A headless
## run
## draws nothing, and a page that asks for the probes (`WebProbe.asked`: a probe drives the night
## from
## its first frame) skips it unless the page asks for it (`?arrival`).
static var arrival_enabled := DisplayServer.get_name() != "headless" and not WebProbe.asked()

## The server to join (`ws://host:port`) the next time this screen opens; empty plays alone.
static var join_url := ""
## With `join_url`: the platform backend's ticket for the night, said in the hello (empty for a
## server with no backend, as on a developer's machine).
static var join_ticket := ""
## With `join_url`: the id of the map the night is on, as the lobby says (the world is built on it
## before the server's WELCOME); empty is the default map.
static var join_map := ""
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
## The profile file a person's night adds its XP to ('' for tests and captures: no file is touched).
static var profile_path := ""
## The lobby the night was entered from (a lobby screen, the Server Browser set them:
## `remember_lobby`) and the way to ask the backend about it; taken once, as `join_url` is. At the
## end of the night the player goes back to this lobby, which the backend opens again for them.
static var return_api: TogetherApi
static var return_lobby := {}

## How a night played alone starts, for a run that is not a person's (`KillBench`): the bot plays,
## filmed from its shoulder, under this tuning (the defaults when null).
static var start_mode := Night.Mode.HUMAN
static var start_tuning: RulesTuning = null
## The seed of a night played alone. -1 (the game) draws a new one for every night, as a game
## server does; before #685 every solo night used `Night.SEED`, so the crane's first prize, the
## zombies' places and every roll after were the same each time. A bench or a tour that must
## repeat sets a number.
static var start_seed := -1
static var shoulder_camera := false

var night: Night
## Gives the team's bots an order from the wheel on Q (`BotWheelDriver`).
var wheel: BotWheelDriver

var _hud: Hud
var _end: HudEndBoard
## The lobby this night came from, if any (`return_lobby`), and the API to ask about it.
var _lobby := {}
var _lobby_api: TogetherApi
## The way out was taken (the clock ran out or Leave was pressed): it is taken only once.
var _left := false
var _loading: LoadingOverlay
var _touch: TouchControls
var _overlay: Control
var _title: UILabel
var _note: UILabel
var _card: Control
## The card and the settings, laid out at the menu's phone factor on a phone (`PhoneScale`, #1205).
var _scaled: PhoneScale
var _resume: UIButton
var _settings_button: UIButton
var _quit: UIButton
var _settings: SettingsScreen


## Keeps the lobby this night is entered from, for the way back at its end. The API is one that
## outlives the screen that made it (`TogetherApi.detached`), since that screen is freed or paused.
static func remember_lobby(api: TogetherApi, held: Dictionary, root: Node) -> void:
	return_api = api.detached(root)
	return_lobby = held


## The look a `--look` value names: `N` is the preset N, `seed:N` a random look made from seed N.
static func look_from_flag(text: String) -> CharacterLook:
	if text.begins_with("seed:"):
		var rng := RandomNumberGenerator.new()
		rng.seed = text.trim_prefix("seed:").to_int()
		return CharacterLook.randomized(rng)
	return CharacterLook.from_preset(text.to_int())


func _exit_tree() -> void:
	MenuPopups.set_night(false)
	# The screen under a night (the Play screen Leave night returns to) is the menu's and runs on
	# the menu's factor: the shell is hidden under it and cannot put the factor back (#1197). A
	# frame later: the factor emits `size_changed`, and this screen's parts have left the tree.
	var window := get_window()
	if window != null and is_inside_tree():
		get_tree().process_frame.connect(
			MenuShell.restore_scale_of.bind(get_tree()), CONNECT_ONE_SHOT
		)


func _ready() -> void:
	super._ready()
	# B (`ui_cancel`) crouches in the night: it must not take the player back to the menu.
	allow_back = false
	# The menu's ambience ends as a night starts to load (the night has its own beds).
	MenuAmbience.stop()
	# The night's HUD owns the popup lane (under its round banner) while this screen is up.
	MenuPopups.set_night(true)
	# The night is made for the player's own UI scale: the menu's phone factor (2, which halves the
	# canvas to 540 units high) would put half the touch buttons off the top. The menu puts the
	# factor back when it shows again (`MenuShell`).
	get_window().content_scale_factor = float(Settings.get_value(SettingsService.UI_SCALE))
	night = Night.new()
	night.warm_up = warm_up_enabled
	night.arrival = arrival_enabled
	night.touch_active = touch_active
	night.own_look = own_look
	if match_settings != null and join_url == "":
		night.match_settings = match_settings
	match_settings = null
	if join_url != "" and not return_lobby.is_empty():
		_lobby = return_lobby
		_lobby_api = return_api
	return_lobby = {}
	return_api = null
	if challenge_path != "":
		night.challenge_board = ChallengeBoard.open(challenge_path)
		# Under the root, like the profile's: the last round's write is sent after this screen has gone.
		night.challenge_uplink = ChallengeUplink.new(
			TogetherApi.new(get_tree().root, TogetherScreen.backend_url())
		)
	if profile_path != "":
		night.profile_store = ProfileStore.open(profile_path, TogetherApi.signed_in)
		# Under the root: the last round's write is sent after this screen has gone.
		night.profile_uplink = ProfileUplink.new(
			TogetherApi.new(get_tree().root, TogetherScreen.backend_url()), night.profile_store
		)
	add_child(night)
	_hud = (load(Hud.SCENE) as PackedScene).instantiate()
	add_child(_hud)
	night.hud = _hud
	# Over the HUD, under the pause overlay; it shows only on a touch device (or when forced).
	_touch = TouchControls.new()
	_touch.state = _hud.state
	_touch.safe_insets_changed.connect(_on_safe_insets_changed)
	_touch.mirrored_changed.connect(_on_mirrored_changed)
	_touch.active_changed.connect(func(active: bool) -> void: _hud.touch_layout = active)
	_touch.layout_changed.connect(func() -> void: _hud.markers.held = _touch.button_boxes())
	_touch.look_gain = _look_gain
	add_child(_touch)
	wheel = BotWheelDriver.new()
	wheel.name = "BotWheelDriver"
	wheel.night = night
	wheel.hud_wheel = _hud.bot_wheel
	wheel.touch = _touch
	add_child(wheel)
	_build_end()
	_build_overlay()
	night.night_over.connect(_on_night_over)
	night.night_closed.connect(_on_night_closed)
	night.ready_to_play.connect(_watch_mouse)
	night.arrival_started.connect(_on_arrival_started)
	night.arrival_ended.connect(_on_arrival_ended)
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


## True while the settings page of the menu is open (a browser test reads it).
func settings_open() -> bool:
	return _settings != null


## The pause card with its Settings while it is on screen, else null: what a person's finger meets
## over the night, which a probe measures alone (#1205).
func card_root() -> Control:
	return _overlay if _overlay != null and _overlay.visible else null


## True while the HUD is on screen (the arrival's show hides it, #1057).
func hud_shown() -> bool:
	return _hud != null and _hud.visible


## True while the centre reticle is on screen (a browser test reads it, #517).
func reticle_shown() -> bool:
	return _hud != null and _hud.reticle.is_visible_in_tree()


## The seed the next solo night starts with: `start_seed`, or a fresh one.
static func solo_seed() -> int:
	return start_seed if start_seed >= 0 else Night.fresh_seed()


func screen_enter() -> void:
	if join_url == "":
		night.shoulder_camera = shoulder_camera
		await night.start(start_mode, solo_seed(), start_tuning)
		return
	var url := join_url
	var mode := Night.Mode.AUTOPILOT if join_as_bot else Night.Mode.HUMAN
	night.shoulder_camera = join_as_bot
	var link := WebSocketLink.new()
	link.ticket = join_ticket
	night.map_id = join_map
	join_url = ""
	join_ticket = ""
	join_map = ""
	join_as_bot = false
	_show_overlay("Joining", "" if link.ticket != "" else url, false)
	night.connect_failed.connect(_on_connect_failed)
	if await night.start_remote(url, mode, JOIN_SECONDS, link):
		_hide_overlay()


func screen_pause() -> void:
	if night.running and not night.state.over:
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
	if _settings != null:
		# Esc, Start or B leaves the settings for the menu, one step back, not out of the menu.
		if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
			_close_settings()
			get_viewport().set_input_as_handled()
		return
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
	_hud.set_safe_insets(insets)
	_end.set_safe_insets(insets)


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
	if night.remote:
		_show_overlay("Menu", "The night goes on around you.", true)
	else:
		_show_overlay("Paused", "The dead wait.", true)


func _resume_night() -> void:
	_drop_settings()
	_hide_overlay()
	night.set_paused(false)


## Takes the card away and gives the night back what `_show_overlay` took: the reticle, the
## scoreboard on Tab and the touch controls. Every way the card goes (Resume, a joined night
## starting) comes here: a night joined online once ran with none of them until a pause and a Resume
## (#517).
func _hide_overlay() -> void:
	_overlay.hide()
	var playing := not night.is_arriving()
	_hud.reticle.set_shown(playing)
	_hud.scoreboard_enabled = playing
	_touch.live = playing


## The helicopter drop is on this screen: the HUD, the reticle and the touch layer give way to it.
func _on_arrival_started() -> void:
	_hud.hide()
	_hud.reticle.set_shown(false)
	_hud.scoreboard_enabled = false
	_touch.live = false


## The drop is over and the night is the player's. A night that ended under it (`Night._on_over`
## closes the show when the end arrives, after this screen has put the board up) is not: the board
## stays alone over the end camera.
func _on_arrival_ended() -> void:
	if _end.visible:
		return
	_hud.show()
	if not _overlay.visible:
		_hud.reticle.set_shown(true)
		_hud.scoreboard_enabled = true
		_touch.live = true


func _on_connect_failed(reason: String) -> void:
	_show_overlay("Could not join", reason, false)


## The night is over: the game's cards give way to the end sequence. The camera is the night's
## (`Night._start_end_camera`); this puts the board over it.
func _on_night_over(_round_reached: int) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_drop_settings()
	_overlay.hide()
	_hud.hide()
	_hud.reticle.set_shown(false)
	_hud.scoreboard_enabled = false
	_touch.live = false
	_end.show_results(
		_hud.state,
		CAPTION_ONLINE if _has_lobby() else CAPTION_ALONE,
		LEAVE_ONLINE if _has_lobby() else LEAVE_ALONE
	)
	_end.set_left(night.state.over_left())
	_show_report()


## The night report and the film credits on the board: what the night paid, from the night's own
## events, and again when the server tells more (the last round's XP can come after the end).
func _show_report() -> void:
	if night.report == null:
		return
	_end.show_report(night.report.model())
	_end.show_credits(night.report.credits_input())
	if not night.report.changed.is_connected(_on_report_changed):
		night.report.changed.connect(_on_report_changed)


func _on_report_changed() -> void:
	if _end.visible and not _left:
		_end.show_report(night.report.model())
		_end.show_credits(night.report.credits_input())


func _process(_delta: float) -> void:
	if _end.visible and not _left:
		_end.set_left(night.state.over_left())


## The server's intermission ran out: everyone goes back to the lobby they came from.
func _on_night_closed() -> void:
	_go_back(true)


## Whether there is a lobby to go back to: a night entered from one, not one joined by an address.
func _has_lobby() -> bool:
	return night.remote and _lobby_api != null and not _lobby.is_empty()


## The way out, once: at the end of the clock (`reopen`) the lobby is asked for until the backend
## has opened it again and the screen is replaced by it; by the player's own press, online, the
## player leaves the lobby too (the host role passes on) and goes back to the screen before the
## night.
func _go_back(reopen: bool) -> void:
	if _left:
		return
	_left = true
	if not _has_lobby():
		UIRouter.pop()
		return
	if not reopen:
		_lobby_api.leave(_lobby)
		UIRouter.pop()
		return
	_end.set_waiting(OPENING)
	_end.leave_button.disabled = true
	var held := await _reopened()
	if not is_inside_tree():
		return
	if held.is_empty():
		UIRouter.pop()
	else:
		LobbyScreen.replace_with_lobby(_lobby_api, held)


## The lobby once the backend has opened it again, or `{}` when it did not within `RETURN_TRIES`
## asks (the lobby is gone: nobody else was left, or the backend is out of reach).
func _reopened() -> Dictionary:
	for _i in RETURN_TRIES:
		var answer := await _lobby_api.refresh(_lobby)
		if not is_inside_tree():
			return {}
		if not answer["ok"]:
			return {}
		if answer["lobby"].get("state") == "open":
			return answer["lobby"]
		await get_tree().create_timer(RETURN_WAIT).timeout
		if not is_inside_tree():
			return {}
	return {}


func _show_overlay(title: String, note: String, can_resume: bool) -> void:
	_drop_settings()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hud.reticle.set_shown(false)
	_hud.scoreboard_enabled = false
	_touch.live = false
	_title.text = title
	_note.text = note
	_fit_taps()
	_resume.visible = can_resume
	_settings_button.visible = can_resume
	_overlay.show()
	(_resume if can_resume else _quit).grab_focus()


## The pause menu's "Leave night": the same way out as the end board's Leave, so the lobby the night
## came from is left too (the host role passes on, and a night with nobody in it ends), never only
## the screen (#1177).
func _leave() -> void:
	_go_back(false)


## The settings page over the card: the same screen as the main menu's, with a Back that comes here.
## Every change is applied and saved by the settings service as it is made.
func _open_settings() -> void:
	if _settings != null:
		return
	_settings = (load(SETTINGS_SCENE) as PackedScene).instantiate() as SettingsScreen
	_settings.embedded = true
	_settings.closed.connect(_close_settings)
	_scaled.add_child(_settings)
	_settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card.hide()
	_settings.focus_initial()


func _close_settings() -> void:
	if _settings == null:
		return
	_drop_settings()
	_settings_button.grab_focus()


## Takes the settings page away and shows the card again.
func _drop_settings() -> void:
	if _settings == null:
		return
	var page := _settings
	_settings = null
	_scaled.remove_child(page)
	page.queue_free()
	_card.show()


func _build_end() -> void:
	_end = HudEndBoard.new()
	_end.name = "EndBoard"
	_end.leave_pressed.connect(_go_back.bind(false))
	add_child(_end)
	_hud.state.changed.connect(_on_hud_changed)


func _on_hud_changed() -> void:
	if _end.visible and not _left:
		_end.refresh(_hud.state)


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.hide()
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	# The night itself stays at the interface size (the HUD and the touch layer are made for it); the
	# card and the settings are the menu's, at the factor of a phone's menu.
	_scaled = PhoneScale.new()
	_scaled.name = "PhoneScale"
	_overlay.add_child(_scaled)
	_card = CenterContainer.new()
	_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scaled.add_child(_card)
	var panel := UIPanel.new()
	panel.variant = UIPanel.Variant.MARQUEE
	_card.add_child(panel)
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
	_settings_button = _button("Settings", UIButton.Variant.SECONDARY)
	_settings_button.pressed.connect(_open_settings)
	_quit = _button("Leave night", UIButton.Variant.SECONDARY)
	_quit.pressed.connect(_leave)
	box.add_child(_resume)
	box.add_child(_settings_button)
	box.add_child(_quit)
	_scaled.resized.connect(_fit_taps)


## The card's buttons are tap targets on a phone: the night runs at the interface size alone, where
## the theme's 79 unit button is 28 px at 844 x 390 (#1192). The card is at the phone factor
## (`_scaled`), so a unit there is bigger.
func _fit_taps() -> void:
	var least := MenuScale.tap_units(get_window(), TouchMode.wanted(get_tree()), _scaled.factor)
	for button: UIButton in [_resume, _settings_button, _quit]:
		button.custom_minimum_size = Vector2(0.0, least)
	# The title's own size (60 units) would take a third of a phone's 540 unit canvas.
	if _scaled.factor > 1.0:
		_title.add_theme_font_size_override(&"font_size", _tokens.size_heading)
	else:
		_title.remove_theme_font_size_override(&"font_size")


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
