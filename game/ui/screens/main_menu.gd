class_name MainMenu
extends UIScreen
## The first screen: the Deadnight sign, and Play, Play together, Settings, Credits and Quit.
##
## Each item opens its screen with its own router transition (Play irises open like a projector
## gate, Settings slides in, Credits burns in like a reel). Quit is left out on the web, where a
## page cannot close itself.

## The items have risen, or were brought in early because another screen covered the menu.
signal entered

const PLAY_SCREEN := "res://ui/screens/night_screen.tscn"
const JOIN_SCREEN := "res://ui/screens/together_screen.tscn"
const CUSTOMIZE_SCREEN := "res://ui/screens/customize_screen.tscn"
const SETTINGS_SCREEN := "res://ui/screens/settings_screen.tscn"
const CREDITS_SCREEN := "res://ui/screens/credits_screen.tscn"
## Seconds after the screen appears before the items rise, so the sign is catching first.
const ITEMS_DELAY := 0.55
## How opaque the plate behind the footer line is.
const FOOTER_PLATE_ALPHA := 0.78

## The delay the next menu waits before its items rise: a test sets a short one; `ITEMS_DELAY` is
## the design value.
static var items_delay := ITEMS_DELAY

var _entrance: Timer
var _entered := false
## What each item's `mouse_filter` and `focus_mode` were before the entrance took them away.
var _interaction := {}

@onready var _sign: NeonSign = %Sign
@onready var _overline: Label = %Overline
@onready var _items: VBoxContainer = %Items
@onready var _footer: Label = %Footer
@onready var _play: UIButton = %Play
@onready var _join: UIButton = %Join
@onready var _customize: UIButton = %Customize
@onready var _settings: UIButton = %Settings
@onready var _credits: UIButton = %Credits
@onready var _quit: UIButton = %Quit


## Whether this platform gets a Quit item.
static func has_quit(web: bool = OS.has_feature("web")) -> bool:
	return not web


func _ready() -> void:
	super._ready()
	_sign.tube_a = _tokens.hot
	_sign.tube_b = _tokens.accent
	_quit.visible = has_quit()
	_style_footer()
	_play.pressed.connect(_open.bind(PLAY_SCREEN, UITransition.Kind.IRIS))
	_join.pressed.connect(_open.bind(JOIN_SCREEN, UITransition.Kind.SLIDE))
	_customize.pressed.connect(_open.bind(CUSTOMIZE_SCREEN, UITransition.Kind.SLIDE))
	_settings.pressed.connect(_open.bind(SETTINGS_SCREEN, UITransition.Kind.SLIDE))
	_credits.pressed.connect(_open.bind(CREDITS_SCREEN, UITransition.Kind.BURN))
	_quit.pressed.connect(get_tree().quit)
	initial_focus = get_path_to(_play)
	# Hidden until the screen has arrived; screen_enter brings them in.
	_hide_for_entrance()


## The footer sits on the parked cars at the bottom of the sky: it takes the full ink and a plate
## of the surface colour behind it, so it reads at 720p over the silhouettes.
func _style_footer() -> void:
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(_tokens.surface, FOOTER_PLATE_ALPHA)
	plate.set_corner_radius_all(_tokens.radius_sm)
	plate.content_margin_left = _tokens.space_md
	plate.content_margin_right = _tokens.space_md
	plate.content_margin_top = _tokens.space_xs
	plate.content_margin_bottom = _tokens.space_xs
	_footer.add_theme_stylebox_override(&"normal", plate)
	_footer.add_theme_color_override(&"font_color", _tokens.ink)
	# The label's own width, not the column's, so the plate hugs the text.
	_footer.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func screen_enter() -> void:
	_sign.ignite()
	UIMotion.fade_in(_overline, ITEMS_DELAY * 0.5)
	UIMotion.fade_in(_footer, ITEMS_DELAY + 0.4)
	if UIMotion.reduced or items_delay <= 0.0:
		finish_entrance.call_deferred()
		return
	# A child Timer, not `SceneTree.create_timer`: it stops while the router disables this screen
	# under another one, and it is freed with the screen.
	_entrance = Timer.new()
	_entrance.one_shot = true
	_entrance.timeout.connect(finish_entrance)
	add_child(_entrance)
	_entrance.start(items_delay)


## A covered menu brings its items in at once (they must be there when the player comes back)
## and takes no focus: the screen over it owns it.
func screen_pause() -> void:
	finish_entrance()


## Takes the focus when the items are there to be seen; before that there is nothing to focus,
## and a key press that asks for the focus (the router does) finds the entrance still going.
func focus_initial() -> void:
	if _entered:
		super.focus_initial()


## Whether the items have risen.
func has_entered() -> bool:
	return _entered


## Brings the items in, and takes the focus only while the menu is the screen the player is on.
## Does nothing the second time.
func finish_entrance() -> void:
	if _entered or not is_inside_tree():
		return
	_entered = true
	if _entrance != null:
		_entrance.queue_free()
		_entrance = null
	_restore_interaction()
	UIMotion.stagger_in(_visible_items())
	if UIRouter.top() == self:
		focus_initial()
	entered.emit()


func _hide_for_entrance() -> void:
	_overline.modulate.a = 0.0
	_footer.modulate.a = 0.0
	for item in _visible_items():
		item.modulate.a = 0.0
		# Transparent is not out of reach: a click or a key must not find an item nobody can see.
		_interaction[item] = [item.mouse_filter, item.focus_mode]
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.focus_mode = Control.FOCUS_NONE


func _restore_interaction() -> void:
	for item: Control in _interaction:
		var before: Array = _interaction[item]
		item.mouse_filter = before[0]
		item.focus_mode = before[1]
	_interaction.clear()


func _visible_items() -> Array[Control]:
	var out: Array[Control] = []
	for child in _items.get_children():
		if (child as Control).visible:
			out.append(child)
	return out


func _open(path: String, kind: UITransition.Kind) -> void:
	if not ResourceLoader.exists(path):
		UIMotion.shake(_items)
		return
	UIRouter.push(path, kind)
