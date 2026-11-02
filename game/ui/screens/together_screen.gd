class_name TogetherScreen
extends UIScreen
## Play with other people: Quick join (a public night with room), Create a night (an invite code
## and link for friends) and Join with a code. A player never sees a server address; the platform
## backend (`TogetherApi`) makes the night, places it on a game server and hands over a ticket.
##
## A page opened with `?room=CODE` joins that night at once, and one opened inside a Discord
## Activity (`?instance_id=...`) lands in the night of its voice channel: both set a static here
## before the screen opens. The address of a game server (`JoinScreen`) is a developer setting,
## shown on the desktop and with `?dev` on the web.

## The player answered the name prompt (a name, or no name).
signal name_decided

const SCREEN := "res://ui/screens/together_screen.tscn"
const NIGHT_SCREEN := "res://ui/screens/night_screen.tscn"
const JOIN_SCREEN := "res://ui/screens/join_screen.tscn"
const FIELD_WIDTH := 620.0
const CODE_LENGTH := 8

## A code to join as soon as the screen opens (`?room=`), and a Discord Activity instance to join
## the night of (`?instance_id=`); each is used once.
static var auto_code := ""
static var auto_instance := ""
## The player chose not to give a name this run (the prompt is not asked again until the next one).
static var name_skipped := false
## Show the server address button (the desktop, or `?dev`).
static var dev_enabled := not OS.has_feature("web")

var api: TogetherApi
var quick_button: UIButton
var create_button: UIButton
var code_field: LineEdit
var join_button: UIButton
var back_button: UIButton
var status: UILabel
## What the invite view shows once a night is made.
var invite_code: UILabel
var invite_link: UILabel
var play_button: UIButton
var copy_link_button: UIButton
var copy_code_button: UIButton
## The name prompt's field and buttons: asked on the first Play together of a player with no name.
var name_field: LineEdit
var name_continue_button: UIButton
var name_skip_button: UIButton

var _menu: VBoxContainer
var _naming: VBoxContainer
var _invite: VBoxContainer
var _lobby := {}
var _busy := false
## The night was found for the player (an invite link, a Discord channel) rather than asked for: it
## waits for a press of Play, which is also the click a browser needs before it lets the game
## capture the mouse and play sound.
var _found := false
var _invite_title: UILabel
## In a Discord Activity: whether the window can read a gamepad (`GamepadProbe`), every second.
var _controller_note: UILabel
var _controller_since := 1.0


func _ready() -> void:
	super._ready()
	api = TogetherApi.new(self, _backend_url())
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := UIPanel.new()
	panel.variant = UIPanel.Variant.MARQUEE
	centre.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", _tokens.space_md)
	panel.add_child(box)
	box.add_child(_label("TOGETHER", UILabel.Style.OVERLINE))
	box.add_child(_label("Play together", UILabel.Style.TITLE))
	status = _label("", UILabel.Style.BODY)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = FIELD_WIDTH
	_menu = _build_menu()
	_invite = _build_invite()
	_naming = _build_naming()
	box.add_child(_menu)
	box.add_child(_invite)
	box.add_child(_naming)
	box.add_child(status)
	_controller_note = _label("", UILabel.Style.BODY)
	_controller_note.name = "ControllerNote"
	_controller_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_controller_note.custom_minimum_size.x = FIELD_WIDTH
	box.add_child(_controller_note)
	back_button = _button("Back", UIButton.Variant.GHOST)
	back_button.pressed.connect(UIRouter.pop)
	box.add_child(back_button)
	if dev_enabled:
		var dev := _button("Server address (developers)", UIButton.Variant.GHOST)
		dev.name = "ServerAddress"
		dev.pressed.connect(func() -> void: UIRouter.push(JOIN_SCREEN, UITransition.Kind.SLIDE))
		box.add_child(dev)
	_show_menu()
	initial_focus = get_path_to(quick_button)


func _process(delta: float) -> void:
	_controller_since += delta
	if _controller_since < 1.0:
		return
	_controller_since = 0.0
	var report := GamepadProbe.read() if in_discord() else {}
	var line := GamepadProbe.note(report)
	_controller_note.text = line if line == "" else "%s (%s)" % [line, GamepadProbe.detail(report)]
	_controller_note.visible = _controller_note.text != ""


func screen_enter() -> void:
	super.screen_enter()
	if auto_code != "":
		var code := auto_code
		auto_code = ""
		code_field.text = code
		_found = true
		await _join()
	elif auto_instance != "":
		var instance := auto_instance
		auto_instance = ""
		api.instance_id = instance
		_found = true
		await _create("Joining your voice channel's night...")


func _build_menu() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", _tokens.space_md)
	var note := _label(
		"Quick join puts you in a night with room. Or make a night and send the code or link to friends.",
		UILabel.Style.BODY
	)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = FIELD_WIDTH
	column.add_child(note)
	quick_button = _button("Quick join", UIButton.Variant.PRIMARY)
	quick_button.name = "QuickJoin"
	quick_button.pressed.connect(_quick)
	column.add_child(quick_button)
	create_button = _button("Create a night", UIButton.Variant.SECONDARY)
	create_button.name = "CreateNight"
	create_button.pressed.connect(func() -> void: await _create("Making your night..."))
	column.add_child(create_button)
	code_field = LineEdit.new()
	code_field.name = "Code"
	code_field.placeholder_text = "Code from a friend"
	code_field.max_length = CODE_LENGTH
	code_field.custom_minimum_size.x = FIELD_WIDTH
	code_field.text_changed.connect(
		func(text: String) -> void:
			var upper := text.to_upper()
			if upper != text:
				var at := code_field.caret_column
				code_field.text = upper
				code_field.caret_column = at
	)
	code_field.text_submitted.connect(func(_text: String) -> void: await _join())
	column.add_child(code_field)
	join_button = _button("Join with the code", UIButton.Variant.SECONDARY)
	join_button.name = "JoinCode"
	join_button.pressed.connect(_join)
	column.add_child(join_button)
	return column


func _build_invite() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", _tokens.space_md)
	_invite_title = _label("YOUR NIGHT IS READY", UILabel.Style.OVERLINE)
	column.add_child(_invite_title)
	invite_code = _label("", UILabel.Style.DISPLAY)
	invite_code.name = "InviteCode"
	column.add_child(invite_code)
	invite_link = _label("", UILabel.Style.BODY)
	invite_link.name = "InviteLink"
	invite_link.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	invite_link.custom_minimum_size.x = FIELD_WIDTH
	column.add_child(invite_link)
	play_button = _button("Play", UIButton.Variant.PRIMARY)
	play_button.name = "PlayInvited"
	play_button.pressed.connect(_enter_night)
	column.add_child(play_button)
	copy_link_button = _button("Copy the link", UIButton.Variant.SECONDARY)
	copy_link_button.name = "CopyLink"
	copy_link_button.pressed.connect(
		func() -> void:
			DisplayServer.clipboard_set(invite_link.text)
			_say("Link copied. Send it to your friends.")
	)
	column.add_child(copy_link_button)
	copy_code_button = _button("Copy the code", UIButton.Variant.SECONDARY)
	copy_code_button.name = "CopyCode"
	copy_code_button.pressed.connect(
		func() -> void:
			DisplayServer.clipboard_set(invite_code.text)
			_say("Code copied.")
	)
	column.add_child(copy_code_button)
	return column


func _build_naming() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", _tokens.space_md)
	column.add_child(_label("WHAT SHOULD WE CALL YOU?", UILabel.Style.OVERLINE))
	var note := _label(
		"This is the name your friends see in a night. You can change it later in the menu, under More.",
		UILabel.Style.BODY
	)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = FIELD_WIDTH
	column.add_child(note)
	name_field = LineEdit.new()
	name_field.name = "PlayerName"
	name_field.placeholder_text = "Your name"
	name_field.max_length = MenuProfile.MAX_NAME
	name_field.custom_minimum_size.x = FIELD_WIDTH
	name_field.text_submitted.connect(func(_text: String) -> void: _decide_name(true))
	column.add_child(name_field)
	name_continue_button = _button("Continue", UIButton.Variant.PRIMARY)
	name_continue_button.name = "NameContinue"
	name_continue_button.pressed.connect(_decide_name.bind(true))
	column.add_child(name_continue_button)
	name_skip_button = _button("Skip, call me Guest", UIButton.Variant.GHOST)
	name_skip_button.name = "NameSkip"
	name_skip_button.pressed.connect(_decide_name.bind(false))
	column.add_child(name_skip_button)
	column.visible = false
	return column


# --- What the buttons do ---


func _quick() -> void:
	if not await _begin("Finding a night..."):
		return
	var found := await api.quick()
	await _finish(found)


func _create(message: String) -> void:
	if not await _begin(message):
		return
	var made := await api.create()
	if made["ok"]:
		_lobby = made["lobby"]
		_show_invite()
		_busy = false
		_say("")
		return
	await _finish(made)


func _join() -> void:
	if not await _begin("Looking for your friends' night..."):
		return
	var joined := await api.join_code(code_field.text)
	await _finish(joined)


## Signs in (once) and locks the buttons; false when it could not.
func _begin(message: String) -> bool:
	if _busy:
		return false
	_busy = true
	_set_enabled(false)
	_say(message)
	if needs_name():
		await _ask_name()
		_say(message)
	var signed := await api.sign_in(_chosen_name())
	if not signed["ok"]:
		_fail(signed)
		return false
	return true


## The name the player gave (the profile's), or "" for `Guest NNNN`.
func _chosen_name() -> String:
	return MenuProfile.load_saved().display_name if MenuProfile.is_named() else ""


## Whether the player is asked for a name now: on the web and the desktop (Discord has its own),
## at the first sign-in of a player with no name, unless they skipped it this run.
func needs_name() -> bool:
	return (
		not in_discord()
		and not name_skipped
		and not TogetherApi.signed_in()
		and not MenuProfile.is_named()
	)


## Shows the name prompt and waits for the answer; a name given is saved in the profile.
func _ask_name() -> void:
	_menu.visible = false
	_invite.visible = false
	_naming.visible = true
	name_field.text = ""
	name_field.grab_focus.call_deferred()
	await name_decided
	_naming.visible = false
	if _lobby.is_empty():
		_show_menu()
	else:
		_show_invite()
	_set_enabled(false)


func _decide_name(give: bool) -> void:
	var saved := MenuProfile.save_name(name_field.text) if give else ""
	if saved == "":
		name_skipped = true
	name_decided.emit()


## An answer that is a lobby goes into its night; one that is not says why.
func _finish(answer: Dictionary) -> void:
	if not answer["ok"]:
		_fail(answer)
		return
	_lobby = answer["lobby"]
	if _found:
		_show_invite()
		_busy = false
		_say("")
		return
	await _enter_night()


func _enter_night() -> void:
	_busy = true
	_set_enabled(false)
	_say("Going in...")
	var pass_to := await api.ticket(_lobby)
	if not pass_to["ok"]:
		_fail(pass_to)
		return
	NightScreen.join_url = server_url_of(pass_to, in_discord())
	NightScreen.join_ticket = pass_to["ticket"]
	_busy = false
	UIRouter.push(NIGHT_SCREEN, UITransition.Kind.IRIS)


func _fail(answer: Dictionary) -> void:
	_busy = false
	_set_enabled(true)
	_say(answer.get("text", "Something went wrong."))
	if _lobby.is_empty():
		_found = false
		_show_menu()
	else:
		_show_invite()


## Where to connect: the address the backend gave, or, in a Discord Activity (where only the
## proxy of the Activity can be reached), the Activity's own host and the path that maps to the
## server.
static func server_url_of(pass_to: Dictionary, in_discord: bool, host: String = "") -> String:
	if not in_discord:
		return pass_to["url"]
	var where := host if host != "" else _page_host()
	return "wss://%s%s" % [where, pass_to["activity_path"]]


# --- The two views ---


func _show_menu() -> void:
	_menu.visible = true
	_invite.visible = false
	_naming.visible = false


func _show_invite() -> void:
	_menu.visible = false
	_naming.visible = false
	_invite.visible = true
	invite_code.text = _lobby["code"]
	invite_link.text = TogetherApi.invite_link(_lobby["code"], _page_url())
	# A night somebody else made needs no invite to hand out.
	_invite_title.text = "YOUR FRIENDS ARE WAITING" if _found else "YOUR NIGHT IS READY"
	invite_link.visible = not _found
	copy_link_button.visible = invite_link.text != invite_code.text and not _found
	copy_code_button.visible = not _found
	_set_enabled(true)
	play_button.grab_focus.call_deferred()


func _set_enabled(enabled: bool) -> void:
	for button: UIButton in [
		quick_button, create_button, join_button, play_button, copy_link_button, copy_code_button
	]:
		if button != null:
			button.disabled = not enabled
	code_field.editable = enabled


func _say(text: String) -> void:
	status.text = text


# --- Where this page is ---


static func _page_url() -> String:
	if not OS.has_feature("web"):
		return ""
	return str(JavaScriptBridge.eval("window.location.origin + window.location.pathname"))


static func _page_host() -> String:
	return str(JavaScriptBridge.eval("window.location.host")) if OS.has_feature("web") else ""


## Whether this page is a Discord Activity: Discord serves it from `<client id>.discordsays.com`,
## and everything it calls goes through that host's URL mappings (`/api`, `/server`).
static func in_discord() -> bool:
	return _page_host().ends_with(".discordsays.com")


## The backend to talk to: `?backend=` (a developer's own), the Activity proxy's `/api` inside
## Discord, else the project's.
func _backend_url() -> String:
	var args := NetArgs.new()
	if args.has("backend"):
		return args.get_string("backend")
	if in_discord():
		return "https://%s/api" % _page_host()
	return TogetherApi.DEFAULT_BACKEND


func _label(text: String, style: UILabel.Style) -> UILabel:
	var label := UILabel.new()
	label.text = text
	label.style = style
	return label


func _button(text: String, variant: UIButton.Variant) -> UIButton:
	var button := UIButton.new()
	button.text = text
	button.variant = variant
	button.custom_minimum_size.x = FIELD_WIDTH
	return button
