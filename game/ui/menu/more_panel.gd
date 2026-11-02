class_name MorePanel
extends MenuPanel
## The More tab: Settings, Credits and Quit (a page cannot close itself, so not on the web), and
## the account line. Sign-in is the platform's and not built: the line says so.

const ROUTES := [
	[&"settings", "Settings", "Sound, picture, controls"],
	[&"credits", "Credits", "Who made this"],
	[&"quit", "Quit", "Back to the desktop"],
]

var _buttons := {}


func _ready() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override(&"separation", 10)
	add_child(column)
	for route: Array in ROUTES:
		if route[0] == &"quit" and not has_quit():
			continue
		var button := MenuItemButton.new()
		button.title = route[1]
		button.subtitle = "" if context.compact else route[2]
		button.set_width(width(context.compact))
		button.name = String(route[0])
		button.pressed.connect(context.request.bind(route[0]))
		column.add_child(button)
		_buttons[route[0]] = button
	var gap := Control.new()
	gap.custom_minimum_size.y = 28.0
	column.add_child(gap)
	column.add_child(MenuLook.heading("Account"))
	var line := MenuLook.label(
		"Playing as %s. Signing in comes with the online platform." % context.profile.display_name,
		MenuLook.SIZE_CAPTION,
		MenuLook.MUTED
	)
	line.autowrap_mode = TextServer.AUTOWRAP_OFF
	column.add_child(line)


## Whether this platform gets a Quit item: a page cannot close itself.
static func has_quit(web: bool = OS.has_feature("web")) -> bool:
	return not web


func width(compact: bool) -> float:
	return 440.0 if compact else 560.0


## The route buttons, by id.
func button(id: StringName) -> MenuItemButton:
	return _buttons.get(id)


func first_focus() -> Control:
	return _buttons[&"settings"]
