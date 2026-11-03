class_name LobbyScreen
extends UIScreen
## The room before a night (docs/design/lobby.md): the code, who is in which seat, who hosts, and
## what to press. Two modes of one screen:
##
## - **Live**: the player is a member of a lobby. The seats follow the backend (`LobbyWatch` polls
##   every two seconds); the host sees *Start the night*, a guest sees who they wait for and, once
##   the host has started, *Play*. *Leave* gives the seat up (the host role passes on).
## - **Preview**: a code looked at before joining (`TogetherApi.preview`): *Waiting room, Ann is
##   hosting, 2 of 4*, or *Night in progress, round 4*, with *Join* (and no Join for a full night).
##
## Open it with `LobbyScreen.show_lobby(api, lobby)` or `LobbyScreen.show_preview(api, preview)`.
## A player never reads an address, an id or a port here: names, seats, a code and a link.

enum Mode { LIVE, PREVIEW }

const SCREEN := "res://ui/screens/lobby_screen.tscn"
const NIGHT_SCREEN := "res://ui/screens/night_screen.tscn"
const FIELD_WIDTH := 620.0
const SEAT_NUMBER_WIDTH := 48.0
const TAG_WIDTH := 96.0
const LEAVE_WIDTH := 150.0
## How long the host's last change waits for another before it is sent (a slider drag is a stream).
const RULES_DELAY := 0.35
## Kept free around the panel when the window is shorter than the screen is tall (it scrolls then).
const PANEL_MARGIN := 120.0

## How many times (every 0.2 s) the bridge's state is read after a press of Share in Discord.
const SHARE_READS_MAX := 600

## For a test: called instead of opening the night screen.
static var opener := Callable()
## The autopilot plays the night this screen opens (`--bot`, for browser probes).
static var play_as_bot := false

var api: TogetherApi
var mode := Mode.LIVE
var lobby := {}
var preview := {}
var watch: LobbyWatch

var code_label: UILabel
var link_label: UILabel
var title_label: UILabel
## The standing line (who the player waits for, what to press) and, under it, the last thing that
## happened ("Bo joined.", a refusal).
var status: UILabel
var note: UILabel
var start_button: UIButton
var play_button: UIButton
var join_button: UIButton
var copy_link_button: UIButton
var copy_code_button: UIButton
## In a Discord Activity: Discord's own window for sending the code to friends, which needs no
## clipboard (`discord-bridge.js`, `shareLink`).
var share_button: UIButton
## What Discord answered to the share (`DiscordShare`): the sentence, and under it the probe line
## with Discord's own numbers and error, which a report quotes.
var share_says: UILabel
var share_probe: UILabel
## Where the text to copy is shown selected when the window cannot copy for the player (a Discord
## Activity whose host blocks the clipboard): Ctrl+C then copies it.
var copy_field: LineEdit
var leave_button: UIButton
## The night's rules: the host's panel moves and is sent to the backend, a guest's shows what the
## host set (read only), and both are fixed once the night starts.
var rules: MatchSettingsPanel

var _rules_title: UILabel
var _rules_timer: Timer
var _rules_waiting: MatchSettings
var _rules_sending := false
var _rules_editable := false
var _rules_shown := false
var _seats: VBoxContainer
var _scroll: ScrollContainer
var _seat_rows: Array[Dictionary] = []
var _busy := false
## The player is on the way into the night: this screen is replaced, and nothing is left behind.
var _entering := false
## The lobby ended for this player (dropped, or gone): no seat to give up.
var _over := false
var _me := ""
var _play_shown := false
var _shares: HBoxContainer
var _share_timer: Timer
var _share_reads := 0
var _share_shown := ""
var _preview_timer: Timer
var _asking_preview := false


## Opens the lobby screen for a lobby the player is a member of.
static func show_lobby(from: TogetherApi, held: Dictionary) -> void:
	UIRouter.push(SCREEN, UITransition.Kind.SLIDE, {"api": from, "lobby": held})


## Opens the screen on what a code says, with Join.
static func show_preview(from: TogetherApi, seen: Dictionary) -> void:
	UIRouter.push(SCREEN, UITransition.Kind.SLIDE, {"api": from, "preview": seen})


## The line under a code that has not been joined: waiting, in progress, or full.
static func preview_text(seen: Dictionary) -> String:
	var count := "%d of %d here" % [int(seen.get("players", 0)), int(seen.get("maxPlayers", 4))]
	if seen.get("full", false):
		return (
			"That night is full (%d of %d)."
			% [int(seen.get("players", 0)), int(seen.get("maxPlayers", 4))]
		)
	if seen.get("state") == "started":
		var round_number: Variant = seen.get("round")
		var where := "Night in progress"
		if round_number != null and int(round_number) > 0:
			where += ", round %d" % int(round_number)
		return "%s. %s." % [where, count]
	return "Waiting room. %s is hosting, %s." % [str(seen.get("hostName", "Someone")), count]


## What the lobby says to the player whose backend id is `me`.
static func status_text(held: Dictionary, me: String) -> String:
	var members: Array = held.get("members", [])
	var max_players := int(held.get("maxPlayers", 4))
	var is_host: bool = held.get("hostId") == me
	if held.get("state") == "started":
		var host := _host_name(held)
		if is_host:
			return "The night is on. Press Play."
		return "%s started the night. Press Play." % host
	if is_host:
		return "%d of %d here. Start whenever you are ready." % [members.size(), max_players]
	return (
		"Waiting for %s to start the night. %d of %d here."
		% [_host_name(held), members.size(), max_players]
	)


## The words for one thing `LobbyWatch.diff` found.
static func event_text(event: Dictionary) -> String:
	var who := str(event.get("name", "Someone"))
	match event["kind"]:
		&"joined":
			return "%s joined." % who
		&"left":
			return "%s left." % who
		&"host":
			return (
				"You are the host now." if event.get("you", false) else "%s is the host now." % who
			)
		&"started":
			return "%s started the night." % who
	return ""


func _ready() -> void:
	super._ready()
	if params.has("api"):
		# Asks through an API that lives under this screen: the screen that opened it is covered, and
		# the router stops the processing of a covered screen, which would leave every request its
		# `HTTPRequest` children made waiting for ever.
		api = (params["api"] as TogetherApi).detached(self)
	mode = Mode.PREVIEW if params.has("preview") else Mode.LIVE
	lobby = params.get("lobby", {})
	preview = params.get("preview", {})
	_me = api.my_id() if api != null else ""
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := UIPanel.new()
	panel.variant = UIPanel.Variant.MARQUEE
	centre.add_child(panel)
	# The panel never grows past the window: a screen taller than it (the copy field and the long
	# link all up) scrolls rather than push Start and Leave off the bottom.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	panel.add_child(_scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", _tokens.space_md)
	_scroll.add_child(box)
	box.minimum_size_changed.connect(_fit)
	get_viewport().size_changed.connect(_fit)
	box.add_child(_label("TOGETHER", UILabel.Style.OVERLINE))
	title_label = _label("The lobby", UILabel.Style.TITLE)
	box.add_child(title_label)
	code_label = _label("", UILabel.Style.DISPLAY)
	code_label.name = "Code"
	box.add_child(code_label)
	link_label = _label("", UILabel.Style.BODY)
	link_label.name = "InviteLink"
	link_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	link_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	link_label.custom_minimum_size.x = FIELD_WIDTH
	box.add_child(link_label)
	_seats = VBoxContainer.new()
	_seats.name = "Seats"
	_seats.add_theme_constant_override(&"separation", _tokens.space_sm)
	box.add_child(_seats)
	_rules_title = _label("THE NIGHT'S RULES", UILabel.Style.OVERLINE)
	box.add_child(_rules_title)
	rules = MatchSettingsPanel.new()
	rules.name = "Rules"
	rules.custom_minimum_size.x = FIELD_WIDTH
	rules.changed.connect(_on_rules_changed)
	box.add_child(rules)
	_rules_timer = Timer.new()
	_rules_timer.one_shot = true
	_rules_timer.wait_time = RULES_DELAY
	_rules_timer.timeout.connect(send_rules)
	add_child(_rules_timer)
	status = _label("", UILabel.Style.BODY)
	status.name = "Status"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = FIELD_WIDTH
	box.add_child(status)
	note = _label("", UILabel.Style.CAPTION)
	note.name = "Note"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = FIELD_WIDTH
	box.add_child(note)
	var actions := _row(box, "Actions")
	start_button = _button("Start the night", UIButton.Variant.PRIMARY, "Start")
	start_button.pressed.connect(start)
	play_button = _button("Play", UIButton.Variant.PRIMARY, "Play")
	play_button.pressed.connect(func() -> void: await _go_in(false))
	join_button = _button("Join", UIButton.Variant.PRIMARY, "Join")
	join_button.pressed.connect(join)
	for primary: UIButton in [start_button, play_button, join_button]:
		_in_row(actions, primary, FIELD_WIDTH - LEAVE_WIDTH - _tokens.space_md, true)
	leave_button = _button("Leave", UIButton.Variant.GHOST, "Leave")
	leave_button.pressed.connect(UIRouter.pop)
	_in_row(actions, leave_button, LEAVE_WIDTH, false)
	var copies := _row(box, "Copies")
	var half := (FIELD_WIDTH - _tokens.space_md) / 2.0
	copy_link_button = _button("Copy the link", UIButton.Variant.SECONDARY, "CopyLink")
	copy_link_button.pressed.connect(
		func() -> void: await _copy(link_label.text, "Link copied. Send it to your friends.")
	)
	_in_row(copies, copy_link_button, half, true)
	copy_code_button = _button("Copy the code", UIButton.Variant.SECONDARY, "CopyCode")
	copy_code_button.pressed.connect(func() -> void: await _copy(code_label.text, "Code copied."))
	_in_row(copies, copy_code_button, half, true)
	_shares = _row(box, "Shares")
	share_button = _button("Share in Discord", UIButton.Variant.SECONDARY, "ShareDiscord")
	share_button.pressed.connect(_share)
	_in_row(_shares, share_button, FIELD_WIDTH, true)
	share_says = _label("", UILabel.Style.BODY)
	share_says.name = "ShareSays"
	share_probe = _label("", UILabel.Style.CAPTION)
	share_probe.name = "ShareProbe"
	for line: UILabel in [share_says, share_probe]:
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size.x = FIELD_WIDTH
		line.visible = false
		box.add_child(line)
	_share_timer = Timer.new()
	_share_timer.wait_time = 0.2
	_share_timer.timeout.connect(_show_share)
	add_child(_share_timer)
	copy_field = LineEdit.new()
	copy_field.name = "CopyField"
	copy_field.editable = false
	copy_field.custom_minimum_size.x = FIELD_WIDTH
	copy_field.visible = false
	box.add_child(copy_field)
	watch = LobbyWatch.new()
	watch.name = "Watch"
	watch.changed.connect(_on_changed)
	watch.happened.connect(_on_happened)
	watch.ended.connect(_on_ended)
	watch.trouble.connect(func() -> void: _say("Lost touch with the lobby. Trying again..."))
	watch.recovered.connect(func() -> void: _on_changed(watch.lobby))
	add_child(watch)
	# A code looked at stays true while the screen is open: the night in progress it said "Waiting
	# room" for is read again every couple of seconds until the player presses Join.
	_preview_timer = Timer.new()
	_preview_timer.wait_time = LobbyWatch.EVERY
	_preview_timer.timeout.connect(refresh_preview)
	add_child(_preview_timer)
	_show()


## The button a player most likely presses: Start, Play or Join, else Leave.
func focus_initial() -> void:
	var target: Control = leave_button
	for button: UIButton in [start_button, play_button, join_button]:
		if button.is_visible_in_tree():
			target = button
			break
	target.grab_focus()


func screen_enter() -> void:
	super.screen_enter()
	if mode == Mode.LIVE and api != null and not _over:
		watch.watch(api, lobby, _me)
	elif mode == Mode.PREVIEW and api != null:
		_preview_timer.start()


func _exit_tree() -> void:
	if watch != null:
		watch.stop()
	if mode != Mode.LIVE or _entering or _over or lobby.is_empty() or api == null:
		return
	# Gone by Back or Esc: the seat goes with it, said from a caller that outlives this screen.
	api.detached(get_tree().root).leave(lobby)


## Whether this player is the host of the lobby they are in.
func is_host() -> bool:
	return mode == Mode.LIVE and lobby.get("hostId") == _me


## The seats as rows of text, in order: `1  Ann  HOST`, `2  (open)`.
func seat_texts() -> Array[String]:
	var out: Array[String] = []
	for row in _seat_rows:
		var parts: Array[String] = []
		for key: String in ["number", "name", "tag"]:
			var text: String = (row[key] as Label).text
			if text != "":
				parts.append(text)
		out.append("  ".join(parts))
	return out


## Reads the code again (the timer does this every two seconds in a preview): the state, the round
## and whether there is room move on while the screen is open.
func refresh_preview() -> void:
	if mode != Mode.PREVIEW or _busy or _asking_preview or preview.is_empty() or api == null:
		return
	_asking_preview = true
	var seen := await api.preview(str(preview.get("code", "")))
	_asking_preview = false
	if mode != Mode.PREVIEW or _busy:
		return
	if seen["ok"]:
		preview = seen["preview"]
		_show()
	elif seen.get("error") == "not_found":
		_preview_timer.stop()
		_on_ended(str(seen.get("text", "")))


## The host presses Start: the backend gives the lobby a game server, and the host goes in.
func start() -> void:
	if _busy or not is_host():
		return
	_busy = true
	_rules_timer.stop()
	_rules_waiting = null
	_set_enabled(false)
	_say("Starting the night...")
	# The rules as the panel shows them now: a change still waiting to be sent goes with the start.
	var started := await api.start(lobby, rules.settings())
	if not started["ok"]:
		_busy = false
		_set_enabled(true)
		_say(started["text"])
		return
	lobby = started["lobby"]
	await _go_in(true)


## A previewed night: Join it. A night in progress takes the player straight in; a waiting room
## becomes their lobby.
func join() -> void:
	if _busy or mode != Mode.PREVIEW:
		return
	_busy = true
	_preview_timer.stop()
	_set_enabled(false)
	_say("Joining...")
	var signed := await api.sign_in()
	var joined := signed if not signed["ok"] else await api.join_code(str(preview.get("code", "")))
	if not joined["ok"]:
		_busy = false
		_set_enabled(true)
		_say(joined["text"])
		if joined.get("error") != "not_found":
			_preview_timer.start()
		return
	lobby = joined["lobby"]
	_me = api.my_id()
	mode = Mode.LIVE
	if lobby.get("state") == "started":
		await _go_in(true)
		return
	_busy = false
	watch.watch(api, lobby, _me)
	_show()
	focus_initial()


## Asks for a ticket and opens the night in place of this screen. `held` says the caller already
## holds the screen busy (Start and Join do); a press of Play does not, and a second one is turned
## away.
func _go_in(held: bool) -> void:
	if _busy and not held:
		return
	_busy = true
	_set_enabled(false)
	_say("Going in...")
	var pass_to := await api.ticket(lobby)
	if not pass_to["ok"]:
		_busy = false
		_set_enabled(true)
		_say(pass_to["text"])
		return
	NightScreen.join_url = TogetherScreen.server_url_of(pass_to, TogetherScreen.in_discord())
	NightScreen.join_ticket = pass_to["ticket"]
	NightScreen.join_as_bot = play_as_bot
	_entering = true
	watch.stop()
	if opener.is_valid():
		opener.call()
	else:
		UIRouter.replace(NIGHT_SCREEN, UITransition.Kind.IRIS)


func _on_changed(held: Dictionary) -> void:
	lobby = held
	_show()


func _on_happened(events: Array) -> void:
	var lines: Array[String] = []
	for event: Dictionary in events:
		var line := event_text(event)
		if line != "":
			lines.append(line)
	if not lines.is_empty():
		_say(" ".join(lines))


func _on_ended(text: String) -> void:
	_over = true
	_set_enabled(true)
	start_button.visible = false
	play_button.visible = false
	join_button.visible = false
	copy_link_button.visible = false
	copy_code_button.visible = false
	_shares.visible = false
	copy_field.visible = false
	leave_button.text = "Back"
	status.text = text if text != "" else TogetherApi.TEXTS["not_found"]
	note.text = ""


# --- What the screen shows ---


func _show() -> void:
	var live := mode == Mode.LIVE
	var held: Dictionary = lobby if live else preview
	code_label.text = str(held.get("code", ""))
	title_label.text = "The lobby" if live else "A night to join"
	var page_link := TogetherApi.invite_link(code_label.text, TogetherScreen._page_url())
	link_label.text = page_link
	link_label.visible = live and page_link != code_label.text
	_show_seats()
	_show_rules()
	var started: bool = live and lobby.get("state") == "started"
	start_button.visible = live and is_host() and not started
	play_button.visible = live and started
	if play_button.visible and not _play_shown:
		# The host has started: the guest's next press is Play, wherever the focus was.
		play_button.grab_focus.call_deferred()
	_play_shown = play_button.visible
	join_button.visible = (not live) and not preview.get("full", false)
	copy_link_button.visible = live and link_label.visible
	copy_code_button.visible = live
	_shares.visible = live and TogetherScreen.can_share()
	leave_button.text = "Leave" if live else "Back"
	if not _over:
		status.text = status_text(lobby, _me) if live else preview_text(preview)
	_set_enabled(not _busy)


## Whether the player can move the panel now.
func rules_editable() -> bool:
	return _rules_editable


## The rules the lobby holds (the usual ones while the host has set none).
func lobby_rules() -> MatchSettings:
	var out := MatchSettings.from_json(lobby.get("settings"))
	return out if out != null else MatchSettings.new()


## How many bots the lobby shows: the setting, and never more than the seats people leave free.
func bots_shown() -> int:
	if mode != Mode.LIVE:
		return 0
	var wanted := rules.settings().bots if _rules_editable else lobby_rules().bots
	var people: int = (lobby.get("members", []) as Array).size()
	return maxi(mini(wanted, int(lobby.get("maxPlayers", 4)) - people), 0)


## The rules on the panel as the web probe reads them: `2x|Auto|20 s`.
func rules_text() -> String:
	return rules.text()


## A control of the host's panel moved: the change is sent once the host stops for a moment.
func _on_rules_changed(value: MatchSettings) -> void:
	if not _rules_editable:
		return
	_show_seats()
	_rules_waiting = value
	_rules_timer.start()


## Sends the host's latest change to the backend (the timer calls this; a test calls it to step by
## hand). One request at a time: a change made while one is on its way follows it.
func send_rules() -> void:
	if _rules_waiting == null or _rules_sending or api == null or not is_host():
		return
	_rules_sending = true
	var value := _rules_waiting
	_rules_waiting = null
	var answer := await api.set_settings(lobby, value)
	_rules_sending = false
	if not answer["ok"]:
		_say(str(answer.get("text", "")))
	if _rules_waiting != null:
		send_rules()


## The panel: the host's while the lobby waits, otherwise what the lobby holds.
func _show_rules() -> void:
	var live := mode == Mode.LIVE
	_rules_title.visible = live
	rules.visible = live
	if not live:
		_rules_editable = false
		_rules_shown = false
		return
	var editable: bool = is_host() and lobby.get("state") != "started"
	# A host's own panel is the truth while they use it: it takes the lobby's rules once, when the
	# role comes to them (the first host, or the next one after the host left).
	if not editable or not _rules_editable:
		rules.set_settings(lobby_rules())
	if editable != _rules_editable or not _rules_shown:
		rules.set_editable(editable)
	_rules_editable = editable
	_rules_shown = true


func _show_seats() -> void:
	var names: Array = []
	var hosts: Array = []
	var away: Array = []
	var max_players := 4
	if mode == Mode.LIVE:
		max_players = int(lobby.get("maxPlayers", 4))
		for member: Dictionary in lobby.get("members", []):
			names.append(str(member["name"]))
			hosts.append(bool(member.get("host", false)))
			away.append(bool(member.get("away", false)))
	else:
		max_players = int(preview.get("maxPlayers", 4))
		for who: Variant in preview.get("names", []):
			names.append(str(who))
			hosts.append(names.size() == 1)
			away.append(false)
	while _seat_rows.size() < max_players:
		_seat_rows.append(_make_seat_row())
	# The bots take the highest seats, as the server seats them (`NightBots`).
	var bot_from := max_players - bots_shown()
	for i in _seat_rows.size():
		var row := _seat_rows[i]
		(row["box"] as Control).visible = i < max_players
		(row["number"] as Label).text = str(i + 1)
		if i >= names.size() and i >= bot_from and i < max_players:
			(row["name"] as Label).text = NightBots.name_for(i + 1)
			(row["name"] as Label).modulate.a = 1.0
			(row["tag"] as Label).text = "BOT"
		elif i < names.size():
			(row["name"] as Label).text = names[i]
			(row["name"] as Label).modulate.a = 1.0
			var tag := "HOST" if hosts[i] else ""
			if away[i]:
				tag = (tag + " AWAY").strip_edges()
			(row["tag"] as Label).text = tag
		else:
			(row["name"] as Label).text = "(open)"
			(row["name"] as Label).modulate.a = 0.5
			(row["tag"] as Label).text = ""


func _make_seat_row() -> Dictionary:
	var box := HBoxContainer.new()
	box.add_theme_constant_override(&"separation", _tokens.space_md)
	var number := _label("", UILabel.Style.BODY)
	number.custom_minimum_size.x = SEAT_NUMBER_WIDTH
	var seat_name := _label("", UILabel.Style.BODY)
	seat_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seat_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var tag := _label("", UILabel.Style.OVERLINE)
	tag.custom_minimum_size.x = TAG_WIDTH
	box.add_child(number)
	box.add_child(seat_name)
	box.add_child(tag)
	_seats.add_child(box)
	return {"box": box, "number": number, "name": seat_name, "tag": tag}


func _set_enabled(enabled: bool) -> void:
	for button: UIButton in [
		start_button, play_button, join_button, copy_link_button, copy_code_button, share_button
	]:
		button.disabled = not enabled
	leave_button.disabled = false


func _say(text: String) -> void:
	note.text = text


## Copies `text` and says `done`; when the window cannot copy for the player (a Discord Activity
## may block it) the text is shown selected with how to copy it: never "copied" for a copy that
## did not happen.
func _copy(text: String, done: String) -> void:
	if await WebClipboard.copy_text(text):
		copy_field.visible = false
		_say(done)
		return
	show_selected(text)
	if WebClipboard.current != null:
		WebClipboard.current.offer(text)
	_say(TogetherScreen.COPY_BLOCKED)


## Opens Discord's share window with the lobby's code in the message: friends read it there and
## paste it into Join with the code (or open the link). Does nothing outside an Activity. What
## Discord answers is shown as it comes (`_show_share`): the hint to pick who to send it to only
## once Discord has not refused, and when it did refuse, that, with the code to copy instead.
func _share() -> void:
	var message := TogetherScreen.SHARE_MESSAGE % code_label.text
	if not DiscordShare.ask(message, code_label.text):
		return
	_share_reads = 0
	_show_share()
	_share_timer.start()


## Reads the bridge's state and shows it; stops reading once nothing more can change.
func _show_share() -> void:
	var state := DiscordShare.read()
	share_says.text = DiscordShare.says(state, code_label.text)
	share_probe.text = DiscordShare.line(state)
	share_says.visible = share_says.text != ""
	share_probe.visible = share_probe.text != ""
	var shown := share_says.text + share_probe.text
	if shown != _share_shown:
		_share_shown = shown
		_scroll_to_share()
	_share_reads += 1
	# Settled, or two minutes of reading (a window left open that long, or an unanswered invite).
	if DiscordShare.settled(state) or _share_reads > SHARE_READS_MAX:
		_share_timer.stop()


## Brings what Discord answered into view: it sits under the buttons, below the panel's edge in a
## short window.
func _scroll_to_share() -> void:
	# After the panel has taken its new height, as for the copy field.
	await get_tree().process_frame
	await get_tree().process_frame
	if _scroll != null and is_instance_valid(share_probe) and share_probe.is_visible_in_tree():
		_scroll.ensure_control_visible(share_probe)
	elif _scroll != null and share_says.is_visible_in_tree():
		_scroll.ensure_control_visible(share_says)


## Shows `text` selected in the copy field and scrolls the field into view, so Ctrl+C copies it.
func show_selected(text: String) -> void:
	copy_field.text = text
	copy_field.visible = true
	copy_field.grab_focus()
	copy_field.select_all()
	# After the panel has taken its new height: until then the field is below the scroll's edge.
	await get_tree().process_frame
	await get_tree().process_frame
	_scroll.ensure_control_visible(copy_field)


static func _host_name(held: Dictionary) -> String:
	for member: Dictionary in held.get("members", []):
		if member.get("host", false):
			return str(member["name"])
	return "The host"


func _label(text: String, style: UILabel.Style) -> UILabel:
	var label := UILabel.new()
	label.text = text
	label.style = style
	return label


func _row(box: VBoxContainer, row_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = row_name
	row.add_theme_constant_override(&"separation", _tokens.space_md)
	box.add_child(row)
	return row


func _in_row(row: HBoxContainer, button: UIButton, width: float, grow: bool) -> void:
	button.custom_minimum_size.x = width
	if grow:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(button)


## Caps the scrolling area at what the window leaves, and gives it all its content needs below that.
func _fit() -> void:
	if _scroll == null or _scroll.get_child_count() == 0:
		return
	var content := (_scroll.get_child(0) as Control).get_combined_minimum_size().y
	content += UIScroll.margins(_scroll).y
	_scroll.custom_minimum_size.y = minf(content, get_viewport_rect().size.y - PANEL_MARGIN)


func _button(text: String, variant: UIButton.Variant, node_name: String) -> UIButton:
	var button := UIButton.new()
	button.text = text
	button.variant = variant
	button.name = node_name
	button.custom_minimum_size.x = FIELD_WIDTH
	return button
