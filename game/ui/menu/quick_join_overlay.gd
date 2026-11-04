class_name QuickJoinOverlay
extends Control
## Quick join from the main menu: a light card over the menu that finds the first open public night
## and goes in, with no Play together screen between (#526). It signs in (once), asks the backend
## for a night (`TogetherApi.quick`, the same call the Play together screen's Quick join makes),
## trades the lobby for a ticket and opens the night. While it searches it says "Finding a
## night..." with a Cancel button. A night it could not find, or a call that failed, says the same
## words the Play together screen says and offers Create a night (a lobby of the player's own).
##
## It asks through its own `TogetherApi`, a child of this overlay, so the menu being covered later
## never leaves a request waiting. The player is asked for no name here: the saved name is used,
## else the backend calls them `Guest NNNN` (the name is a setting under More).

## The overlay is gone: `joined` when the player went into a night, `to_lobby` when they made a
## night of their own; both false when they cancelled or closed it.
signal finished(joined: bool, to_lobby: bool)

enum State { IDLE, SEARCHING, FAILED, DONE }

const NIGHT_SCREEN := "res://ui/screens/night_screen.tscn"
const SEARCHING := "Finding a night..."
const GOING_IN := "Going in..."
const WIDTH := 460.0
## For a test: `Callable(parent: Node) -> TogetherApi` answers instead of the backend.
static var api_factory := Callable()
## For a test: called instead of opening the night screen.
static var opener := Callable()

var state := State.IDLE
var api: TogetherApi
var status: UILabel
## The map of the night it found, as a ticket, from the moment it has found one.
var map_card: MapCard
var cancel_button: UIButton
var create_button: UIButton
var close_button: UIButton

var _tokens := UITokens.active()
var _cancelled := false
var _lobby := {}


func _ready() -> void:
	name = "QuickJoin"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var scrim := ColorRect.new()
	scrim.color = MenuLook.SCRIM
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	var panel := UIPanel.new()
	panel.variant = UIPanel.Variant.MARQUEE
	centre.add_child(panel)
	# The card scrolls rather than grow past the canvas: a failure is a sentence, and a card of it
	# was 975 units high, more than a phone's 540 or an interface size of Large (#980).
	var scroll := UIFitScroll.new()
	scroll.name = "Scroll"
	scroll.margin = float(_tokens.space_md)
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", _tokens.space_md)
	scroll.add_child(box)
	box.add_child(_label("QUICK JOIN", UILabel.Style.OVERLINE))
	status = _label(SEARCHING, UILabel.Style.TITLE)
	status.name = "Status"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = WIDTH
	box.add_child(status)
	map_card = MapCard.new()
	map_card.name = "Map"
	map_card.set_width(WIDTH)
	map_card.focus_mode = Control.FOCUS_NONE
	map_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_card.visible = false
	box.add_child(map_card)
	create_button = _button("Create a night", UIButton.Variant.PRIMARY, "CreateNight")
	create_button.pressed.connect(create_night)
	box.add_child(create_button)
	cancel_button = _button("Cancel", UIButton.Variant.GHOST, "Cancel")
	cancel_button.pressed.connect(cancel)
	box.add_child(cancel_button)
	close_button = _button("Close", UIButton.Variant.GHOST, "Close")
	close_button.pressed.connect(cancel)
	box.add_child(close_button)
	_show_buttons()


## Starts the search; pressed again while one is running, it shows the card again and keeps the
## search (a Cancel pressed a moment ago is taken back).
func run() -> void:
	if state == State.SEARCHING:
		_cancelled = false
		show()
		_show_buttons()
		return
	state = State.SEARCHING
	_cancelled = false
	_lobby = {}
	map_card.visible = false
	show()
	_say(SEARCHING)
	_show_buttons()
	var pass_to := await _search()
	if _cancelled:
		await _drop()
		return
	if not pass_to["ok"]:
		_fail(pass_to)
		return
	_go_in(pass_to)


## Cancel while searching, Close after a failure: back to the menu. A call already out is let
## finish and undone (the night it joined is left) so the player is not held by a search they
## ended.
func cancel() -> void:
	if state == State.SEARCHING:
		_cancelled = true
		hide()
		return
	_finish(false, false)


## After a failure: a lobby of the player's own, with the code to send, in its screen.
func create_night() -> void:
	if state != State.FAILED:
		return
	state = State.SEARCHING
	_say("Making your night...")
	_show_buttons()
	var made := await api.create_lobby()
	if _cancelled:
		if made["ok"]:
			_lobby = made["lobby"]
		await _drop()
		return
	if not made["ok"]:
		_fail(made)
		return
	state = State.DONE
	LobbyScreen.show_lobby(api, made["lobby"])
	_finish(false, true)


## The text a player reads now.
func text() -> String:
	return status.text


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	# The tabs behind the card stay where they are while it is up.
	if MenuNav.tab_step(event) != 0:
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_cancel"):
		cancel()
		get_viewport().set_input_as_handled()


## Signs in, finds a night and takes its ticket: `{"ok": true, ...ticket}` or the failure.
func _search() -> Dictionary:
	api = api_factory.call(self) if api_factory.is_valid() else _own_api()
	var room := ActivityRoom.current
	if room != null:
		# A Discord Activity signs in while the menu shows; its session is the one to use.
		if room.state == ActivityRoom.State.IDLE or room.state == ActivityRoom.State.FAILED:
			room.prepare()
		if not await room.until_ready():
			return {"ok": false, "text": room.failure}
	var signed := await api.sign_in(_chosen_name())
	if not signed["ok"] or _cancelled:
		return signed
	var found := await api.quick()
	if not found["ok"]:
		return found
	_lobby = found["lobby"]
	_show_map()
	if _cancelled:
		return found
	return await api.ticket(_lobby)


## The card of the night the search found: where the player is about to go.
func _show_map() -> void:
	map_card.info = MapRegistry.of_lobby(_lobby)
	map_card.visible = true


func _own_api() -> TogetherApi:
	return TogetherApi.new(self, TogetherScreen.backend_url())


func _go_in(pass_to: Dictionary) -> void:
	state = State.DONE
	_say(GOING_IN)
	NightScreen.join_url = TogetherScreen.server_url_of(pass_to, TogetherScreen.in_discord())
	NightScreen.join_ticket = pass_to["ticket"]
	NightScreen.join_map = MapRegistry.of_lobby(_lobby).id
	NightScreen.remember_lobby(api, _lobby, get_tree().root)
	if opener.is_valid():
		opener.call()
	else:
		UIRouter.push(NIGHT_SCREEN, UITransition.Kind.IRIS)
	_finish(true, false)


## A search the player cancelled ended: the night it found is left, then the card goes.
func _drop() -> void:
	if not _lobby.is_empty() and api != null:
		await api.detached(get_tree().root).leave(_lobby)
	_finish(false, false)


func _fail(answer: Dictionary) -> void:
	state = State.FAILED
	map_card.visible = false
	_say(str(answer.get("text", "Something went wrong.")))
	_show_buttons()


func _finish(joined: bool, to_lobby: bool) -> void:
	state = State.DONE
	finished.emit(joined, to_lobby)
	queue_free()


func _say(line: String) -> void:
	status.text = line


## Searching offers Cancel; a failure offers Create a night and Close.
func _show_buttons() -> void:
	var failed := state == State.FAILED
	# What the backend says about a failure is a sentence, read at the size of one.
	status.style = UILabel.Style.BODY if failed else UILabel.Style.TITLE
	create_button.visible = failed
	close_button.visible = failed
	cancel_button.visible = not failed
	if is_inside_tree():
		_keep_focus_inside()
	if is_inside_tree() and visible:
		_focus_default.call_deferred()


## The card's first button takes the focus, unless the card has gone since it asked.
func _focus_default() -> void:
	if is_queued_for_deletion() or state == State.DONE or not visible:
		return
	(create_button if state == State.FAILED else cancel_button).grab_focus()


## The arrows and Tab stay on the card's visible buttons: nothing behind it can be reached.
func _keep_focus_inside() -> void:
	var shown: Array[UIButton] = []
	for button: UIButton in [create_button, cancel_button, close_button]:
		if button.visible:
			shown.append(button)
	for i in shown.size():
		var button := shown[i]
		button.focus_neighbor_left = button.get_path()
		button.focus_neighbor_right = button.get_path()
		button.focus_neighbor_top = shown[(i - 1 + shown.size()) % shown.size()].get_path()
		button.focus_neighbor_bottom = shown[(i + 1) % shown.size()].get_path()
		button.focus_previous = button.focus_neighbor_top
		button.focus_next = button.focus_neighbor_bottom


## The name the player gave (the profile's), or "" for `Guest NNNN`.
func _chosen_name() -> String:
	return MenuProfile.load_saved().display_name if MenuProfile.is_named() else ""


func _label(line: String, style: UILabel.Style) -> UILabel:
	var label := UILabel.new()
	label.text = line
	label.style = style
	return label


func _button(line: String, variant: UIButton.Variant, node_name: String) -> UIButton:
	var button := UIButton.new()
	button.text = line
	button.variant = variant
	button.name = node_name
	button.custom_minimum_size.x = WIDTH
	return button
