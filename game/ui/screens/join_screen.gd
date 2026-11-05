class_name JoinScreen
extends UIScreen
## Join a night on a game server: an address to type (it starts as this machine's own server) and
## Join, which opens the night screen on that server. Hosting is `godot --headless --path game --
## --server` (`docs/research/testing-multiplayer.md`); this screen only joins.

const NIGHT_SCREEN := "res://ui/screens/night_screen.tscn"
const DEFAULT_URL := "ws://localhost:8910"
## The game server the project runs on Railway (docs/research/testing-multiplayer.md): what the web
## build starts with, since a browser has no server of its own on this machine.
const PUBLIC_URL := "wss://deadnight-server-production.up.railway.app"
const FIELD_WIDTH := 620.0

var address: LineEdit
var join_button: UIButton
var back_button: UIButton


## A server address as a player types it, made into a WebSocket URL: nothing is the default
## server; `host` and `host:port` are `ws://` with the default port; `http(s)` is `ws(s)`.
static func normalize(text: String) -> String:
	var url := text.strip_edges()
	if url == "":
		return DEFAULT_URL
	if url.begins_with("https://"):
		url = "wss://" + url.trim_prefix("https://")
	elif url.begins_with("http://"):
		url = "ws://" + url.trim_prefix("http://")
	elif not url.contains("://"):
		url = "ws://" + url
		if not url.trim_prefix("ws://").contains(":"):
			url += ":%d" % NetWire.DEFAULT_PORT
	return url.trim_suffix("/")


func _ready() -> void:
	super._ready()
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := UIPanel.new()
	panel.variant = UIPanel.Variant.MARQUEE
	centre.add_child(panel)
	# The card scrolls rather than grow past the canvas (a phone held sideways is 540 units, #980).
	var scroll := UIFitScroll.new()
	scroll.name = "Scroll"
	scroll.margin = float(_tokens.space_md)
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", _tokens.space_md)
	scroll.add_child(box)
	box.add_child(_label("TOGETHER", UILabel.Style.OVERLINE))
	box.add_child(_label("Join a night", UILabel.Style.TITLE))
	var note := _label(
		(
			"The address of a game server: the public one (filled in on the web), this machine's"
			+ " own (ws://localhost:8910), or a host and port."
		),
		UILabel.Style.BODY
	)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = FIELD_WIDTH
	box.add_child(note)
	address = LineEdit.new()
	UiSounds.wire_field(address)
	address.text = PUBLIC_URL if OS.has_feature("web") else DEFAULT_URL
	address.placeholder_text = DEFAULT_URL
	address.custom_minimum_size.x = FIELD_WIDTH
	address.select_all_on_focus = true
	address.text_submitted.connect(func(_text: String) -> void: join())
	box.add_child(address)
	join_button = _button("Join", UIButton.Variant.PRIMARY)
	join_button.pressed.connect(join)
	box.add_child(join_button)
	back_button = _button("Back", UIButton.Variant.GHOST)
	back_button.pressed.connect(UIRouter.pop)
	box.add_child(back_button)
	initial_focus = get_path_to(address)
	resized.connect(func() -> void: TapFloor.fit(self, TapFloor.phone_canvas(size)))
	TapFloor.fit(self, TapFloor.phone_canvas(size))


## Opens the night on the server named in the field.
func join() -> void:
	NightScreen.join_url = normalize(address.text)
	UIRouter.push(NIGHT_SCREEN, UITransition.Kind.IRIS)


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
