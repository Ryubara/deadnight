class_name BotPings
extends RefCounted
## What a bot does about a person's ping (bots plan, phase 5, `docs/research/bots.md#team-roles-and-
## communication`): a small set where each ping has one meaning (`PingBoard`). The bot reads the
## marks in the frame, the same ones a person sees over the lot, and only the marks of people (a
## bot's own are no order to the others).
##
## - `here`: go and hold this place for as long as the mark stands: the one bot nearest to it goes
##   (ties to the lowest seat) and stays within `HOLD_RADIUS` metres, fighting from there;
## - `enemy`: shoot this one: the zombie is the first target while the bot sees it (it still stays
##   out of reach of any it must not fight);
## - `downed`: raise this one first, whatever the order of need says (`BotRevive.pinged`);
## - `door`: buy it when it can be paid, which the errands do (`BotErrands`);
## - `ammo`: an ammunition spot, left to the shop errands for now.
##
## Pure functions of the frame's marks and the bot's beliefs.

## Metres within which a bot holding a place counts itself there, and the radius it is sent to.
const HOLD_RADIUS := 3.0
const HOLD_STAND := 2.0


## The marks the people of the night have up, `{from, kind, pos, subject, left}`, from the frame's
## `pings`. `teammates` is the bot's table of the other players (it says who is a bot).
static func marks(frame: Dictionary, teammates: Dictionary) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var board: Dictionary = frame.get("pings", {})
	for from: int in board:
		if teammates.get(from, {}).get("bot", false):
			continue
		var mark: Dictionary = board[from]
		(
			found
			. append(
				{
					"from": from,
					"kind": mark.get("kind", &""),
					"pos": mark.get("pos", Vector3.INF),
					"subject": mark.get("subject", 0),
					"left": float(mark.get("left", 0.0)),
				}
			)
		)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["from"] < b["from"])
	return found


## The zombie a person marked as an enemy, if the bot may shoot at it now (it is among `targets`,
## the believed zombies in sight), else -1.
static func enemy(found: Array[Dictionary], targets: Array[Dictionary]) -> int:
	for mark in found:
		if mark["kind"] != PingBoard.ENEMY:
			continue
		for contact in targets:
			if contact["id"] == int(mark["subject"]):
				return contact["id"]
	return -1


## The downed player a person marked, or 0.
static func downed(found: Array[Dictionary]) -> int:
	for mark in found:
		if mark["kind"] == PingBoard.DOWNED:
			return int(mark["subject"])
	return 0


## The place this bot is sent to hold, or `Vector3.INF`: the bot nearest the mark of kind `here`
## goes, and only while it is farther than `HOLD_RADIUS` from it. `bots` are the other bots as the
## beliefs keep them (up and not busy: the caller leaves out the ones that are not free).
static func hold_place(
	found: Array[Dictionary], me: int, here: Vector3, bots: Array[Dictionary]
) -> Vector3:
	for mark in found:
		if mark["kind"] != PingBoard.HERE or not (mark["pos"] as Vector3).is_finite():
			continue
		var place: Vector3 = mark["pos"]
		var mine := _flat(here, place)
		for other in bots:
			var theirs := _flat(other["pos"], place)
			if theirs < mine or (is_equal_approx(theirs, mine) and int(other["id"]) < me):
				return Vector3.INF
		return place if mine > HOLD_RADIUS else Vector3.INF
	return Vector3.INF


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
