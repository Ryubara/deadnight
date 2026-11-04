class_name MenuPopups
extends Control
## The popup lane for everything that is not a night: top centre of every menu screen, in the
## router's layer under the film. Whatever hears a progression event outside a night hands it to
## `announce` and the card drops in the same way the night's do (`PopupLane`). While a night's
## screen is up the night's own HUD owns the lane (under its round banner) and this one stands down.
##
## The router's canvas layer gives a Control no parent rectangle, so this one takes the viewport's
## size itself, as the controller hint does.

## Where the cards start: under the menu's tab bar and the profile ticket, not over them.
const TOP := 100.0

## The overlay of this game, or null (a test that has none).
static var instance: MenuPopups

var lane := PopupLane.new()

var _link: PopupLink
var _night_up := false


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	name = "MenuPopups"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	lane.name = "Lane"
	lane.margin = TOP
	add_child(lane)
	_link = PopupLink.new(lane)
	get_viewport().size_changed.connect(_fit)
	_fit()


## Shows the progression events of `events` (the server's `level_up`, `tier_up`, `unlock_earned`,
## a finished `challenge_advanced`) as cards, unless a night is up.
static func announce(events: Array) -> void:
	if instance == null or not is_instance_valid(instance) or instance._night_up:
		return
	for event: Dictionary in events:
		instance.lane.on_event(event)


## A night's screen is up (or gone): its HUD takes the lane, and the cards of the menu are put away.
static func set_night(up: bool) -> void:
	if instance == null or not is_instance_valid(instance):
		return
	instance._night_up = up
	if up:
		instance.lane.clear()


func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
