class_name MainMenu
extends UIScreen
## The first screen: the player's soldier in the live drive-in with the tab shell over it (Play,
## Loadout, Shop, Challenges, More; `docs/research/main-menu.md`). The shell and its panels read
## the account profile and the challenge board and know no route: they ask through the context's
## `action`, and this screen turns each ask into a router push (Play irises open like a projector
## gate, Settings slides in, Credits burns in like a reel). Quit is left out on the web, where a
## page cannot close itself.

## The shell is built and the screen is the one on show.
signal entered

const PLAY_SCREEN := "res://ui/screens/play_screen.tscn"
const JOIN_SCREEN := "res://ui/screens/together_screen.tscn"
const SETTINGS_SCREEN := "res://ui/screens/settings_screen.tscn"
const CREDITS_SCREEN := "res://ui/screens/credits_screen.tscn"
## The route of each ask a panel can make. Play together opens the Play together screen. Quick
## join has no route: it joins from the menu (`QuickJoinOverlay`) and reaches a screen only by its
## fallback, a night of the player's own (#526).
const ROUTES := {
	&"solo": [PLAY_SCREEN, UITransition.Kind.IRIS],
	&"together": [JOIN_SCREEN, UITransition.Kind.SLIDE],
	&"settings": [SETTINGS_SCREEN, UITransition.Kind.SLIDE],
	&"credits": [CREDITS_SCREEN, UITransition.Kind.BURN],
}

## Builds the challenge board the menu reads (a test or a capture sets its own).
static var board_factory := Callable()

var shell: MenuShell

var _entered := false
var _quick_join: QuickJoinOverlay


## Whether this platform gets a Quit item.
static func has_quit(web: bool = OS.has_feature("web")) -> bool:
	return MorePanel.has_quit(web)


func _ready() -> void:
	super._ready()
	shell = MenuShell.new()
	shell.name = "Shell"
	shell.context.profile = MenuProfile.load_saved()
	shell.context.board = _open_board()
	shell.context.action.connect(_on_action)
	add_child(shell)


func screen_enter() -> void:
	# The sounds a night needs load while the player reads the menu, not behind the night's bar.
	Audio.start_background_preload()
	var sign_node := (shell.panel(MenuTab.Id.PLAY) as PlayPanel).sign_node
	if sign_node != null:
		sign_node.ignite()
	shell.view.set_active(true)
	# A name given on the way (the Play together prompt) shows on the plate at once.
	shell.set_profile(MenuProfile.load_saved())
	_entered = true
	focus_initial()
	entered.emit()


## A covered menu draws nothing: the stage's viewport stops until the screen above is gone.
func screen_pause() -> void:
	shell.view.set_active(false)


func screen_resume() -> void:
	shell.view.set_active(true)
	shell.set_profile(MenuProfile.load_saved())
	focus_initial()


## Focus goes to the tab's first control, so a key or the pad starts in the panel.
func focus_initial() -> void:
	if _entered and shell != null:
		shell.focus_panel()


## Whether the screen has been shown.
func has_entered() -> bool:
	return _entered


func _open_board() -> Object:
	if board_factory.is_valid():
		return board_factory.call()
	# The challenge tracker (#399) provides the board; until it is in the project the menu shows
	# no challenges rather than failing.
	for entry in ProjectSettings.get_global_class_list():
		if entry["class"] == &"ChallengeBoard":
			return (load(entry["path"]) as GDScript).call(&"open")
	return null


func _on_action(id: StringName) -> void:
	if id == &"quit":
		get_tree().quit()
		return
	if id == &"quick_join":
		_quick_join_now()
		return
	if not ROUTES.has(id):
		return
	var route: Array = ROUTES[id]
	if not ResourceLoader.exists(route[0]):
		UIMotion.shake(shell)
		return
	UIRouter.push(route[0], route[1])


## Quick join: a card over the menu that finds the first open public night and goes in. Pressed
## again while it searches, it is the same search.
func _quick_join_now() -> void:
	if is_instance_valid(_quick_join):
		_quick_join.run()
		return
	_quick_join = QuickJoinOverlay.new()
	_quick_join.finished.connect(_on_quick_join_finished)
	add_child(_quick_join)
	_quick_join.run()


func _on_quick_join_finished(joined: bool, to_lobby: bool) -> void:
	_quick_join = null
	if not joined and not to_lobby:
		focus_initial()
