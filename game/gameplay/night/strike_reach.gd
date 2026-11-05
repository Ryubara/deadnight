class_name StrikeReach
extends RefCounted
## Whether a dead is within reach of the quick melee, as this client sees the night (#1285): what
## the phone's Strike button waits for. It reads only the client's picture (`ClientState`), so it
## costs no network traffic, runs the same on a local night and on a game server, and says nothing
## the server would not agree with: the same rule the bots strike by (`BotMotor`), the blow's own
## reach on the ground between the player and the dead.
##
## The button comes up at the blow's reach and goes at `LEAVE_MARGIN` metres past it, so a dead
## that shuffles on the edge does not flicker it, and a thumb that is already on it is not dropped
## by a step back.

## Metres past the blow's reach a dead may go before the button goes.
const LEAVE_MARGIN := 0.3

var _reach := -1.0
var _up := false


## Whether the button should show now. Call once a frame or less; it keeps the edge's memory.
func update(state: ClientState) -> bool:
	_up = _reached(state, _limit() + (LEAVE_MARGIN if _up else 0.0))
	return _up


func is_up() -> bool:
	return _up


## The blow's reach in metres (the quick melee's definition, read once).
func reach() -> float:
	return _limit()


func _limit() -> float:
	if _reach < 0.0:
		_reach = WeaponCatalog.quick_melee().melee_range
	return _reach


## A living dead within `limit` metres on the ground, the player on its feet.
func _reached(state: ClientState, limit: float) -> bool:
	if state == null or not state.has_frame():
		return false
	var me := state.me()
	if me.is_empty() or me.get("downed", false):
		return false
	var here: Vector3 = me.get("pos", Vector3.ZERO)
	for zombie in state.zombies:
		if int(zombie.get("mode", 0)) == ZombieBody.Mode.DYING:
			continue
		var there: Vector3 = zombie["position"]
		if Vector2(there.x - here.x, there.z - here.z).length() < limit:
			return true
	return false
