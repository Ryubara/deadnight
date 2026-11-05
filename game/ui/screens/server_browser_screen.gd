class_name ServerBrowserScreen
extends UIScreen
## The Server Browser (Deadnight #1180): the public nights a player can join, one row each, and one
## press on a row puts the player in that night. It lists both **lobbies** that wait for their host
## and **matches** in progress (`NightEntry`), tells them apart on the row (`NightRow`), and keeps
## itself current while it is open (`NightListFeed`: every few seconds, inside the backend's rate
## limit).
##
## The Play tab opens it, the Play together screen opens it, and a lobby opens it over itself: from
## inside a lobby a press on a row **moves** the player to that night (the backend takes them out of
## the lobby they were in), and the lobby screen they left is freed without a second `leave`. Back
## from the browser, with nothing pressed, returns to the lobby as it was.
##
## A row's press: `join_code` of the row's code, then, for a night in progress, a ticket and the
## night; for a waiting room, the lobby screen. Nothing stops on the way: no name is asked (the
## saved name is used, else `Guest NNNN`), no confirmation, and a refusal (the night filled, or
## ended, while the list was open) is a sentence under the title and a fresh list.
##
## Open it with `ServerBrowserScreen.open(api)` (or `open(api, lobby)` from inside a lobby).

const SCREEN := "res://ui/screens/server_browser_screen.tscn"
const NIGHT_SCREEN := "res://ui/screens/night_screen.tscn"
## The frame's room round the panel and its widest, in units; a phone held sideways is 540 units
## tall.
const MARGIN := Vector2(120.0, 70.0)
const MARGIN_COMPACT := Vector2(28.0, 18.0)
const MAX_WIDTH := 1360.0
## Below this many units tall the rows are the phone's.
const COMPACT_BELOW := 700.0
const FOOTER_WIDTH := 300.0

const LOADING := "Looking for nights..."
const EMPTY := "No nights are open right now. Make one, and your friends find it here."
const JOINING := "Joining %s..."
const FULL := "That night is full."
const SLOT_EMPTY := "No nights right now"
const SLOT_LOADING := "Looking for nights..."
const SLOT_FAILED := "Could not load the list"
const GONE := "That night has ended. Here is the list again."

## For a test: `Callable(parent: Node) -> TogetherApi` answers instead of the backend.
static var api_factory := Callable()
## For a test: called instead of opening the night screen.
static var opener := Callable()

var api: TogetherApi
var feed: NightListFeed
var compact := false
## The lobby the browser was opened from (its screen is under this one), else empty.
var from_lobby := {}

var title_label: UILabel
var count_label: UILabel
## The standing line (what the list holds, or why it does not) and, under it, the last thing that
## happened (a night that filled or ended, a refusal).
var status: UILabel
var note: UILabel
var scroll: UIScroll
var rows_box: VBoxContainer
## The dashed place in the list while there is no night to show.
var slot: NightSlot
var refresh_button: UIButton
var create_button: UIButton
var back_button: UIButton

var _panel: UIPanel
var _frame: CenterContainer
var _rows: Array[NightRow] = []
var _entries: Array[NightEntry] = []
var _busy := false
var _entered_once := false
var _signed := false
## The sign-in failed (the feed never started, so it has no failed state of its own).
var _sign_in_failed := false
## The focus has been placed on the list (or its Create button) once; after that the player's place
## is theirs.
var _placed := false


## Opens the browser over the screen that is up. `from` is the lobby the player is in, when they
## open it from its screen.
static func open(from_api: TogetherApi = null, from := {}) -> void:
	UIRouter.push(SCREEN, UITransition.Kind.SLIDE, {"api": from_api, "lobby": from})


func _ready() -> void:
	super._ready()
	allow_back = true
	if params.get("api") is TogetherApi:
		api = (params["api"] as TogetherApi).detached(self)
	elif api_factory.is_valid():
		api = api_factory.call(self)
	else:
		api = TogetherApi.new(self, TogetherScreen.backend_url())
	from_lobby = params.get("lobby", {})
	_build()
	feed = NightListFeed.new()
	feed.name = "Feed"
	feed.loading.connect(_on_loading)
	feed.updated.connect(_on_updated)
	feed.failed.connect(_on_failed)
	feed.waiting.connect(_on_waiting)
	add_child(feed)
	resized.connect(_fit)
	_fit()
	_show_state()


func _build() -> void:
	_frame = CenterContainer.new()
	_frame.name = "Frame"
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_frame)
	_panel = UIPanel.new()
	_panel.name = "Panel"
	_panel.variant = UIPanel.Variant.MARQUEE
	_frame.add_child(_panel)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, _tokens.space_md)
	_panel.add_child(pad)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override(&"separation", _tokens.space_sm)
	pad.add_child(column)
	var head := HBoxContainer.new()
	column.add_child(head)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	names.add_child(_label("SERVER BROWSER", UILabel.Style.OVERLINE))
	title_label = _label("Nights to join", UILabel.Style.TITLE)
	title_label.name = "Title"
	names.add_child(title_label)
	count_label = _label("", UILabel.Style.OVERLINE)
	count_label.name = "Count"
	count_label.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(count_label)
	status = _label("", UILabel.Style.BODY)
	status.name = "Status"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status)
	note = _label("", UILabel.Style.BODY)
	note.name = "Note"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.visible = false
	column.add_child(note)
	scroll = UIScroll.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	rows_box = VBoxContainer.new()
	rows_box.name = "Rows"
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_box.add_theme_constant_override(&"separation", _tokens.space_sm)
	scroll.add_child(rows_box)
	slot = NightSlot.new()
	slot.name = "Slot"
	rows_box.add_child(slot)
	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override(&"separation", _tokens.space_md)
	column.add_child(footer)
	refresh_button = _button("Refresh", UIButton.Variant.SECONDARY, "Refresh")
	refresh_button.pressed.connect(refresh)
	footer.add_child(refresh_button)
	create_button = _button("Create a night", UIButton.Variant.SECONDARY, "CreateNight")
	create_button.pressed.connect(create_night)
	footer.add_child(create_button)
	back_button = _button("Back", UIButton.Variant.GHOST, "Back")
	back_button.pressed.connect(UIRouter.pop)
	footer.add_child(back_button)
	initial_focus = get_path_to(refresh_button)


# --- The screen's life ---


func screen_enter() -> void:
	super.screen_enter()
	_begin()


func screen_pause() -> void:
	feed.stop()


## Back from a night or a lobby the browser sent the player into: the list is read again at once, as
## the player may have left a night that is gone by now.
func screen_resume() -> void:
	_busy = false
	allow_back = true
	_set_enabled(true)
	super.screen_resume()
	if _signed:
		_tell("")
		feed.start(api)


func _exit_tree() -> void:
	if feed != null:
		feed.stop()


## Signs in (once) and starts the list.
func _begin() -> void:
	if _entered_once:
		return
	_entered_once = true
	_sign_in_failed = false
	_say(LOADING)
	var signed := await api.sign_in(_chosen_name())
	if not is_inside_tree():
		return
	if not signed["ok"]:
		_sign_in_failed = true
		_fail(str(signed.get("text", "Something went wrong.")))
		return
	_signed = true
	feed.start(api)


## Refresh: the list now (the feed turns away a press that comes too soon after the last ask). After
## a failure it signs in again first.
func refresh() -> void:
	if _busy:
		return
	if not _signed:
		_entered_once = false
		_begin()
		return
	if feed.refresh(true) and _entries.is_empty():
		_say(LOADING)


# --- What the feed says ---


func _on_loading() -> void:
	if _entries.is_empty():
		_say(LOADING)
		_show_state()


func _on_updated(entries: Array[NightEntry], _total: int) -> void:
	_show_rows(entries)
	_show_state()
	_keep_lobby()


func _on_failed(text: String, _reason: String) -> void:
	_fail(text)


## The backend's limit holds the list for a moment: what is on show stays.
func _on_waiting(_seconds: float) -> void:
	_tell(TogetherApi.TEXTS["too_many_requests"])


func _fail(text: String) -> void:
	_say(text)
	refresh_button.text = "Try again"
	_show_state()


## The dashed place says what the list is doing while it has no row to show.
func _show_slot() -> void:
	slot.visible = _entries.is_empty()
	if _sign_in_failed or feed == null or feed.state == NightListFeed.State.FAILED:
		slot.text = SLOT_FAILED
	elif feed.state == NightListFeed.State.LOADED:
		slot.text = SLOT_EMPTY
	else:
		slot.text = SLOT_LOADING


# --- The rows ---


## Shows `entries`: a row for each, kept as it is when it shows the same (the list refreshes while
## the player moves through it, and the focus must stay on the row they are on).
func _show_rows(entries: Array[NightEntry]) -> void:
	var focused_code := _focused_code()
	var focused_index := -1
	for index in _rows.size():
		if _rows[index].has_focus():
			focused_index = index
	_entries = entries
	var same := _rows.size() == entries.size()
	if same:
		for index in entries.size():
			if _rows[index].entry == null or _rows[index].entry.code != entries[index].code:
				same = false
				break
	if same:
		for index in entries.size():
			if not entries[index].same_as(_rows[index].entry):
				_rows[index].entry = entries[index]
	else:
		_rebuild_rows(entries)
		_restore_focus(focused_code, focused_index)


func _rebuild_rows(entries: Array[NightEntry]) -> void:
	for row in _rows:
		rows_box.remove_child(row)
		row.queue_free()
	_rows.clear()
	for entry in entries:
		var row := NightRow.new()
		row.name = "Night_%s" % entry.code
		row.compact = compact
		row.entry = entry
		row.here = not from_lobby.is_empty() and entry.id == str(from_lobby.get("id", ""))
		row.pressed.connect(join.bind(row))
		rows_box.add_child(row)
		_rows.append(row)
	_link_focus()


## Up and Down walk the rows and then the footer; the first row's Up and the footer's sides stay
## put.
func _link_focus() -> void:
	for index in _rows.size() - 1:
		_rows[index].focus_neighbor_bottom = _rows[index].get_path_to(_rows[index + 1])
		_rows[index + 1].focus_neighbor_top = _rows[index + 1].get_path_to(_rows[index])
	if _rows.is_empty():
		return
	_rows[0].focus_neighbor_top = _rows[0].get_path_to(_rows[0])
	var last := _rows[_rows.size() - 1]
	last.focus_neighbor_bottom = last.get_path_to(refresh_button)
	for button: Control in [refresh_button, create_button, back_button]:
		button.focus_neighbor_top = button.get_path_to(last)


func _focused_code() -> String:
	var holder := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if holder is NightRow and (holder as NightRow).entry != null:
		return (holder as NightRow).entry.code
	return ""


## The row the player was on keeps the focus when the list was rebuilt; when that night is gone, the
## row now in its place (or the last one) takes it. The focus is not stolen from the footer or the
## pointer.
func _restore_focus(code: String, index: int) -> void:
	if code == "":
		return
	for row in _rows:
		if row.entry.code == code:
			row.grab_focus.call_deferred()
			return
	if _rows.is_empty():
		create_button.grab_focus.call_deferred()
	else:
		_rows[clampi(index, 0, _rows.size() - 1)].grab_focus.call_deferred()


## The status line, the count, the buttons and the focus for what the list holds now.
func _show_state() -> void:
	var waiting := 0
	var running := 0
	for entry in _entries:
		if entry.is_match():
			running += 1
		else:
			waiting += 1
	var loaded: bool = feed != null and feed.state == NightListFeed.State.LOADED
	if loaded:
		refresh_button.text = "Refresh"
		_say(EMPTY if _entries.is_empty() else summary(waiting, running))
	count_label.text = (
		""
		if _entries.is_empty()
		else "%d NIGHT%s" % [_entries.size(), "" if _entries.size() == 1 else "S"]
	)
	var is_empty: bool = _entries.is_empty() and loaded
	_show_slot()
	create_button.variant = UIButton.Variant.PRIMARY if is_empty else UIButton.Variant.SECONDARY
	_place_focus(is_empty)


## `2 waiting to start, 3 in progress`: which of the two there are, in words.
static func summary(waiting: int, running: int) -> String:
	var parts: Array[String] = []
	if waiting > 0:
		parts.append("%d waiting to start" % waiting)
	if running > 0:
		parts.append("%d in progress" % running)
	return ", ".join(parts) + ". Press a night to join it."


## The first time the list is up, the focus goes to its first row (or to Create a night when it is
## empty), unless the player has already moved it: after that their place is theirs and a refresh
## never takes it.
func _place_focus(is_empty: bool) -> void:
	if _placed or not is_inside_tree() or feed.state != NightListFeed.State.LOADED:
		return
	_placed = true
	var holder := get_viewport().gui_get_focus_owner()
	if holder != null and is_ancestor_of(holder) and holder != refresh_button:
		return
	if is_empty:
		create_button.grab_focus.call_deferred()
	elif not _rows.is_empty():
		_rows[0].grab_focus.call_deferred()


# --- The press ---


## A press on a row: join its night, from the menu or from inside another lobby.
func join(row: NightRow) -> void:
	var entry := row.entry
	if _busy or entry == null:
		return
	if row.here:
		# The night the player opened the browser from: back to it, as it was.
		UIRouter.pop()
		return
	if entry.full:
		_tell(FULL)
		feed.refresh(true)
		return
	_hold(true)
	row.joining = true
	_tell(JOINING % entry.map().title)
	var signed := await api.sign_in(_chosen_name())
	var joined := signed if not signed["ok"] else await api.join_code(entry.code)
	if not is_inside_tree():
		return
	if not joined["ok"]:
		_hold(false)
		row.joining = false
		_tell(GONE if joined.get("error") == "not_found" else str(joined["text"]))
		return
	var lobby: Dictionary = joined["lobby"]
	if lobby.get("state") == "started":
		await _enter_night(lobby, row)
		return
	var moving := not from_lobby.is_empty()
	_leave_held_lobby()
	row.joining = false
	if moving:
		# Opened from a lobby: the browser is replaced by the new lobby, so Leave goes back to where
		# the old one was.
		LobbyScreen.replace_with_lobby(api, lobby)
	else:
		LobbyScreen.show_lobby(api, lobby)


## A night in progress: its ticket, and the night.
func _enter_night(lobby: Dictionary, row: NightRow) -> void:
	var pass_to := await api.ticket(lobby)
	if not is_inside_tree():
		return
	if not pass_to["ok"]:
		_hold(false)
		row.joining = false
		_tell(str(pass_to["text"]))
		return
	var moving := not from_lobby.is_empty()
	_leave_held_lobby()
	row.joining = false
	NightScreen.join_url = TogetherScreen.server_url_of(pass_to, TogetherScreen.in_discord())
	NightScreen.join_ticket = pass_to["ticket"]
	NightScreen.join_map = MapRegistry.of_lobby(lobby).id
	NightScreen.join_as_bot = LobbyScreen.play_as_bot
	NightScreen.remember_lobby(api, lobby, get_tree().root)
	if opener.is_valid():
		opener.call()
	elif moving:
		UIRouter.replace(NIGHT_SCREEN, UITransition.Kind.IRIS)
	else:
		UIRouter.push(NIGHT_SCREEN, UITransition.Kind.IRIS)


## Create a night: a lobby of the player's own, with the code to send (it moves them out of the one
## they were in, as joining does).
func create_night() -> void:
	if _busy:
		return
	_hold(true)
	_tell("Making your night...")
	var signed := await api.sign_in(_chosen_name())
	var made := signed if not signed["ok"] else await api.create_lobby()
	if not is_inside_tree():
		return
	if not made["ok"]:
		_hold(false)
		_tell(str(made["text"]))
		return
	var moving := not from_lobby.is_empty()
	_leave_held_lobby()
	if moving:
		LobbyScreen.replace_with_lobby(api, made["lobby"])
	else:
		LobbyScreen.show_lobby(api, made["lobby"])


## The lobby screen under this one is the lobby the player has just left for another night: it is
## freed (it says nothing to the backend, which moved the player), and the new screen takes this
## one's place (`replace`), so nothing of the old lobby or of this list is left under it.
func _leave_held_lobby() -> void:
	if from_lobby.is_empty():
		return
	for screen in UIRouter.screens():
		var lobby_screen := screen as LobbyScreen
		if (
			lobby_screen != null
			and str(lobby_screen.lobby.get("id", "")) == str(from_lobby.get("id", ""))
		):
			lobby_screen.moved_on()
	from_lobby = {}
	for row in _rows:
		row.here = false


## While the browser is open over a lobby, the lobby is asked about with each list, as its own
## screen (covered, so not polling) would: a member quiet for a minute is dropped from a lobby with
## others in it.
func _keep_lobby() -> void:
	if from_lobby.is_empty() or _busy:
		return
	var held := from_lobby
	var answer := await api.refresh(held)
	if not is_inside_tree() or from_lobby.is_empty():
		return
	if not answer["ok"] and str(answer.get("error", "")) in ["not_member", "not_found"]:
		from_lobby = {}
		for row in _rows:
			row.here = false


## Rows and footer are locked while a press is on its way (and the screen cannot be left: the answer
## would have no screen to land on).
func _hold(on: bool) -> void:
	_busy = on
	allow_back = not on
	_set_enabled(not on)
	if on:
		feed.stop()
	elif _signed:
		feed.start(api)


func _set_enabled(enabled: bool) -> void:
	for control: Control in [refresh_button, create_button, back_button]:
		(control as BaseButton).disabled = not enabled
	for row in _rows:
		row.disabled = not enabled


# --- Layout ---


## The panel as big as the canvas leaves it: a phone's 540 units, a desktop's 1080.
func _fit() -> void:
	var viewport := size
	if viewport.x <= 0.0 or viewport.y <= 0.0:
		return
	compact = viewport.y < COMPACT_BELOW
	var margin := MARGIN_COMPACT if compact else MARGIN
	_panel.custom_minimum_size = Vector2(
		minf(MAX_WIDTH, viewport.x - margin.x * 2.0), viewport.y - margin.y * 2.0
	)
	for row in _rows:
		row.compact = compact
	slot.compact = compact
	# A phone's 540 units keep the rows: the big title goes, and the count stands beside the
	# overline.
	title_label.visible = not compact
	count_label.size_flags_vertical = (
		Control.SIZE_SHRINK_CENTER if compact else Control.SIZE_SHRINK_END
	)
	# The footer is three buttons: a desktop's keep their width; a phone's share what the panel has.
	for button: UIButton in [refresh_button, create_button, back_button]:
		button.custom_minimum_size.x = 0.0 if compact else FOOTER_WIDTH
		button.size_flags_horizontal = (
			Control.SIZE_EXPAND_FILL if compact else Control.SIZE_SHRINK_BEGIN
		)


# --- The words the probes and tests read ---


## The rows on show, as `CODE kind people/seats map host`, top to bottom (a browser test reads it).
func rows_text() -> String:
	var out: Array[String] = []
	for entry in _entries:
		out.append(
			(
				"%s %s %d/%d %s %s"
				% [
					entry.code,
					"match" if entry.is_match() else "lobby",
					entry.players,
					entry.max_players,
					entry.map_id,
					entry.host_name
				]
			)
		)
	return "|".join(out)


## The row of a code, or null.
func row_of(code: String) -> NightRow:
	for row in _rows:
		if row.entry != null and row.entry.code == code:
			return row
	return null


func rows() -> Array[NightRow]:
	return _rows


func is_busy() -> bool:
	return _busy


func _say(line: String) -> void:
	status.text = line


func _tell(line: String) -> void:
	note.text = line
	note.visible = line != ""


## The name the player gave (the profile's), or "" for `Guest NNNN`.
func _chosen_name() -> String:
	return MenuProfile.load_saved().display_name if MenuProfile.is_named() else ""


func _label(text: String, style: UILabel.Style) -> UILabel:
	var label := UILabel.new()
	label.text = text
	label.style = style
	return label


func _button(text: String, variant: UIButton.Variant, node_name: String) -> UIButton:
	var button := UIButton.new()
	button.text = text
	button.variant = variant
	button.name = node_name
	return button
