class_name WeaponEquipSync
extends RefCounted
## Puts in each player's hand the weapon the server says it holds. It reads only what a client
## hears: every frame names the weapon of every player (`players[id].weapon`), and when that
## differs from what the body shows, the body's `PlayerAnimation` is told to `equip` the class
## (`WeaponHoldMap`). The local player and the others go through the same line; a player who
## joins late shows the weapon of their first frame.

var _bodies: Callable
## What each body was last given, by player id.
var _shown: Dictionary[int, StringName] = {}


## `bodies` maps a player id to the `Player` that draws it (or null): the server's body in this
## process, a drawn avatar on a second machine.
func _init(state: ClientState, bodies: Callable) -> void:
	_bodies = bodies
	state.event_received.connect(_on_event)


## The weapon id last given to a player's body, or &"" before any.
func shown(player_id: int) -> StringName:
	return _shown.get(player_id, &"")


func _on_event(event: Dictionary) -> void:
	if event["type"] != &"frame":
		return
	var players: Dictionary = event["players"]
	for player_id: int in players:
		_sync(player_id, players[player_id]["weapon"])


func _sync(player_id: int, weapon: StringName) -> void:
	if weapon == &"" or _shown.get(player_id) == weapon:
		return
	var body := _bodies.call(player_id) as Player
	var animation := body.get_node_or_null(^"AnimationTree") as PlayerAnimation if body else null
	if animation == null:
		return
	animation.equip_weapon(weapon)
	_shown[player_id] = weapon
