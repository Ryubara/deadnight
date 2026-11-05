class_name MorePanel
extends MenuPanel
## The More tab: Settings, Credits and Quit (a page cannot close itself, so not on the web), and
## the player's name. The name is what other players see in a night (a guest's, sent when the game
## signs in); in a Discord Activity the server nickname is used instead.

const NAME_NOTE := "Your name in a night. Left empty you are a Guest."
const DISCORD_NOTE := "In Discord your name in the server is used."

const ROUTES := [
	[&"settings", "Settings", "Sound, picture, controls"],
	[&"credits", "Credits", "Who made this"],
	[&"quit", "Quit", "Back to the desktop"],
]

## Where the player types the name others see; empty means `Guest NNNN` online.
var name_field: LineEdit

var _buttons := {}


func _ready() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	hold(column)
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
	if TogetherScreen.in_discord():
		var from_discord := MenuLook.label(DISCORD_NOTE, MenuLook.SIZE_CAPTION, MenuLook.MUTED)
		from_discord.autowrap_mode = TextServer.AUTOWRAP_OFF
		column.add_child(from_discord)
		return
	name_field = LineEdit.new()
	name_field.name = "PlayerName"
	name_field.placeholder_text = MenuProfile.DEFAULT_NAME
	name_field.max_length = MenuProfile.MAX_NAME
	UiSounds.wire_field(name_field)
	name_field.custom_minimum_size.x = width(context.compact)
	TapFloor.fit(name_field, context.compact)
	name_field.text = _saved_name()
	name_field.text_submitted.connect(func(_text: String) -> void: save_name())
	name_field.focus_exited.connect(save_name)
	column.add_child(name_field)
	var line := MenuLook.label(NAME_NOTE, MenuLook.SIZE_CAPTION, MenuLook.MUTED)
	line.autowrap_mode = TextServer.AUTOWRAP_OFF
	column.add_child(line)


## Keeps what is typed as the player's name when it changed: the plate shows it, and the next online
## sign-in sends it (the session of the old name is dropped, so the next night has the new one).
func save_name() -> void:
	if name_field == null or MenuProfile.clean_name(name_field.text) == _saved_name():
		return
	var saved := MenuProfile.save_name(name_field.text)
	context.profile.display_name = saved if saved != "" else MenuProfile.DEFAULT_NAME
	name_field.text = saved
	TogetherApi.forget()
	context.profile_changed.emit()


## The name the profile holds, or "" when nobody gave one.
func _saved_name() -> String:
	return MenuProfile.load_saved().display_name if MenuProfile.is_named() else ""


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
