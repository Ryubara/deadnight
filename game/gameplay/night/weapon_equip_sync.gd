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
## Whether each body's weapon was last dressed in the re-cut skin, by player id.
var _recut: Dictionary[int, bool] = {}


## `bodies` maps a player id to the `Player` that draws it (or null): the server's body in this
## process, a drawn avatar on a second machine.
func _init(state: ClientState, bodies: Callable) -> void:
	_bodies = bodies
	state.event_received.connect(_on_event)


## The weapon id last given to a player's body, or &"" before any.
func shown(player_id: int) -> StringName:
	return _shown.get(player_id, &"")


## Whether the weapon last given to a player's body wears the re-cut skin.
func shown_recut(player_id: int) -> bool:
	return _recut.get(player_id, false)


## Whether a frame's entry for a player has the weapon in the hand re-cut: the tier it carries in
## `arms` (`[ammo, reserve, tier]`) is above 0. A weapon lost, or swapped for another, takes its
## tier
## with it: the next weapon's own says.
static func is_recut(entry: Dictionary) -> bool:
	var arms: Dictionary = entry.get("arms", {})
	var counts: Array = arms.get(entry["weapon"], [])
	return counts.size() > 2 and int(counts[2]) > 0


func _on_event(event: Dictionary) -> void:
	if event["type"] != &"frame":
		return
	var players: Dictionary = event["players"]
	for player_id: int in players:
		var entry: Dictionary = players[player_id]
		_sync(player_id, entry["weapon"], is_recut(entry))


func _sync(player_id: int, weapon: StringName, recut: bool) -> void:
	if weapon == &"":
		return
	var body := _bodies.call(player_id) as Player
	var animation := body.get_node_or_null(^"AnimationTree") as PlayerAnimation if body else null
	if animation == null:
		return
	var changed: bool = _shown.get(player_id) != weapon
	if changed:
		animation.equip(weapon)
		_shown[player_id] = weapon
	# A weapon that was put in the hand re-cut shows its skin finished; one that was re-cut while it
	# was in the hand (the bench) has it sweep on.
	if changed or _recut.get(player_id, false) != recut:
		animation.set_recut(recut, not changed)
		_recut[player_id] = recut
