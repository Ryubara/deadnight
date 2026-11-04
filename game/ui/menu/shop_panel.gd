class_name ShopPanel
extends MenuPanel
## The Shop tab: the prize counter. The look catalogue's gated colours are real entries (what
## they ask for is `LookUnlocks.describe`; the three cloth channels share one palette, so the
## main colour's stand for them); the categories the design lists are placeholders,
## marked "coming", because the stub economy does not exist yet (docs/design/progression.md). A
## press buys nothing: the client only shows, the server will award.

## The categories of the design, shown as placeholders until the economy is built.
const CATEGORIES: Array[String] = [
	"Costumes", "Finishes", "Flashlight housings", "Screen reels", "Horn and emotes"
]

var _list: VBoxContainer
var _scroll: ScrollContainer
var _balance: Label
var _status: Label


func _ready() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override(&"separation", 10)
	add_child(column)
	column.add_child(MenuLook.heading("Prize counter", "Prices are placeholders", MenuLook.AMBER))
	_balance = MenuLook.label("", MenuLook.SIZE_BODY, MenuLook.INK)
	column.add_child(_balance)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 8)
	_scroll.add_child(_list)
	_status = MenuLook.label("", MenuLook.SIZE_CAPTION, MenuLook.MUTED)
	column.add_child(_status)
	refresh()


func width(compact: bool) -> float:
	return 640.0 if compact else 1100.0


## The entries the shop shows: {title, how, real}.
func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var unlocks := LookUnlocks.new()
	unlocks.level = context.profile.level()
	var gates := LookCatalog.palette_gates()
	for key: String in gates:
		var parts := key.split("/")
		var channel := StringName(parts[0])
		if channel != &"primary":
			continue
		var index := int(parts[1])
		var palette := LookCatalog.palette(channel)
		if index >= palette.size():
			continue
		var entry: Dictionary = palette[index]
		var gate: Dictionary = gates[key]
		(
			out
			. append(
				{
					"title": "%s: %s" % [LookCatalog.COLOUR_TITLES[channel], entry["label"]],
					"how":
					"Yours" if unlocks.is_unlocked(channel, entry["id"], gate) else _asks(gate),
					"real": true,
				}
			)
		)
	for category in CATEGORIES:
		out.append({"title": category, "how": "Coming", "real": false})
	return out


## What a gate asks for, in a few words.
static func _asks(gate: Dictionary) -> String:
	if gate.has("level"):
		return "Level %d" % int(gate["level"])
	return "An order"


func rows() -> Array[MenuItemButton]:
	var out: Array[MenuItemButton] = []
	for child in _list.get_children():
		if child is MenuItemButton:
			out.append(child)
	return out


func balance_text() -> String:
	return _balance.text


func refresh() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_balance.text = "You have %s stubs" % MenuNav.grouped(context.profile.stubs)
	_status.text = ""
	for entry in entries():
		var row := MenuItemButton.new()
		row.title = entry["title"]
		row.note = entry["how"]
		row.placeholder = not entry["real"]
		row.set_width(fit_width(context.compact) - UIScroll.side_room(_scroll))
		row.pressed.connect(_on_pressed.bind(entry))
		_list.add_child(row)


func _on_pressed(entry: Dictionary) -> void:
	_status.text = (
		"Buying comes with the prize counter." if entry["real"] else "Not in the shop yet."
	)
