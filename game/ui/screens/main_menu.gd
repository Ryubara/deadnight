class_name MainMenu
extends UIScreen
## The first screen: the Deadnight sign, and Play, Settings, Credits and Quit.
##
## Each item opens its screen with its own router transition (Play irises open like a projector
## gate, Settings slides in, Credits burns in like a reel). Quit is left out on the web, where a
## page cannot close itself.

## The items have risen, or were brought in early because another screen covered the menu.
signal entered

const PLAY_SCREEN := "res://ui/screens/night_screen.tscn"
const JOIN_SCREEN := "res://ui/screens/join_screen.tscn"
const CUSTOMIZE_SCREEN := "res://ui/screens/customize_screen.tscn"
const SETTINGS_SCREEN := "res://ui/screens/settings_screen.tscn"
const CREDITS_SCREEN := "res://ui/screens/credits_screen.tscn"
## Seconds after the screen appears before the items rise, so the sign is catching first.
const ITEMS_DELAY := 0.55

## The delay the next menu waits before its items rise: a test sets a short one; `ITEMS_DELAY` is
## the design value.
static var items_delay := ITEMS_DELAY

var _entrance: Timer
var _entered := false

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
	_play.pressed.connect(_open.bind(PLAY_SCREEN, UITransition.Kind.IRIS))
	_join.pressed.connect(_open.bind(JOIN_SCREEN, UITransition.Kind.SLIDE))
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
	UIMotion.stagger_in(_visible_items())
	if UIRouter.top() == self:
		focus_initial()
	entered.emit()


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
