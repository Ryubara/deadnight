class_name MomentsBench
extends RefCounted
## What the suites of the odd and together stats share (#1074): a tally that knows the lot, and
## events made the way the rules and the server make them (their keys, one frame a tick).

var tally := NightTally.new()
var tick_count := 0
## Player id -> where the frame puts them (a frame names a position for each of these).
var positions: Dictionary = {}
## Circuit id -> whether it is on, said by each frame once it is not empty.
var circuits: Dictionary = {}


func _init() -> void:
	tally.know(RulesFixture.tuning(), "drive_in")


func feed(event: Dictionary) -> void:
	tally.observe(event)


## Lets `seconds` pass, one frame at the end of it, as the server tells every tick.
func wait(seconds: float) -> void:
	tick_count += roundi(seconds / NightMoments.TICK_SECONDS)
	var players := {}
	for id: int in positions:
		players[id] = {"pos": positions[id]}
	var frame := {"type": &"frame", "tick": tick_count, "players": players}
	if not circuits.is_empty():
		frame["circuits"] = circuits.duplicate()
	feed(frame)


func join(id: int, bot := false) -> void:
	feed({"type": &"player_added", "player_id": id, "bot": bot})


func start(round_number: int) -> void:
	feed(
		{
			"type": &"round_started",
			"round": round_number,
			"zombie_count": 3,
			"special_id": &"",
			"boss_count": 0
		}
	)


func finish(round_number: int, standing: Array) -> void:
	feed({"type": &"round_ended", "round": round_number, "special_id": &"", "standing": standing})


func kill(killer: int, type := &"walker", melee := false, zone := &"body") -> void:
	feed(
		{
			"type": &"zombie_removed",
			"zombie_id": 1,
			"zombie_type": type,
			"boss": false,
			"cause": &"killed",
			"killer_id": killer,
			"zone": zone,
			"melee": melee,
			"shattered": false,
		}
	)


func shot(id: int, weapon: StringName, ammo := 5, reserve := 50) -> void:
	feed(
		{
			"type": &"shot_fired",
			"shooter_id": id,
			"weapon_id": weapon,
			"ammo": ammo,
			"reserve": reserve
		}
	)


func hold(id: int, weapon: StringName) -> void:
	feed({"type": &"weapon_equipped", "player_id": id, "weapon_id": weapon})


func board(id: int, window := &"w1") -> void:
	feed({"type": &"board_repaired", "barricade_id": window, "boards": 1, "player_id": id})


func buy(id: int, item: StringName, price := 100) -> void:
	feed({"type": &"purchase_made", "player_id": id, "item_id": item, "price": price, "detail": {}})


func down(id: int) -> void:
	feed({"type": &"player_downed", "player_id": id, "cause": &"blow"})


func n(id: int, stat: StringName) -> int:
	return tally.count(id, stat)
