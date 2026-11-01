class_name MainMenu
extends UIScreen
## The first screen: the Deadnight sign, and Play, Settings, Credits and Quit.
##
## Each item opens its screen with its own router transition (Play irises open like a projector
## gate, Settings slides in, Credits burns in like a reel). Quit is left out on the web, where a
## page cannot close itself.

const PLAY_SCREEN := "res://ui/screens/play_screen.tscn"
const CUSTOMIZE_SCREEN := "res://ui/screens/customize_screen.tscn"
const SETTINGS_SCREEN := "res://ui/screens/settings_screen.tscn"
const CREDITS_SCREEN := "res://ui/screens/credits_screen.tscn"
## Seconds after the screen appears before the items rise, so the sign is catching first.
const ITEMS_DELAY := 0.55

@onready var _sign: NeonSign = %Sign
@onready var _overline: Label = %Overline
@onready var _items: VBoxContainer = %Items
@onready var _footer: Label = %Footer
@onready var _play: UIButton = %Play
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
	_play.pressed.connect(_open.bind(PLAY_SCREEN, UITransition.Kind.IRIS))
	_customize.pressed.connect(_open.bind(CUSTOMIZE_SCREEN, UITransition.Kind.SLIDE))
	_settings.pressed.connect(_open.bind(SETTINGS_SCREEN, UITransition.Kind.SLIDE))
	_credits.pressed.connect(_open.bind(CREDITS_SCREEN, UITransition.Kind.BURN))
	_quit.pressed.connect(get_tree().quit)
	initial_focus = get_path_to(_play)
	# Hidden until the screen has arrived; screen_enter brings them in.
	_hide_for_entrance()


func screen_enter() -> void:
	_sign.ignite()
	UIMotion.fade_in(_overline, ITEMS_DELAY * 0.5)
	UIMotion.fade_in(_footer, ITEMS_DELAY + 0.4)
	await get_tree().create_timer(0.0 if UIMotion.reduced else ITEMS_DELAY).timeout
	UIMotion.stagger_in(_visible_items())
	focus_initial()


func _hide_for_entrance() -> void:
	_overline.modulate.a = 0.0
	_footer.modulate.a = 0.0
	for item in _visible_items():
		item.modulate.a = 0.0


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
