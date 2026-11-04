class_name XpMeter
extends RefCounted
## One player's XP for the night so far, in hundredths. It is fed the changes a `NightTally`
## answers (`observe`), so a server adds to it a kill at a time and a client reads it as the night
## goes; the one-off awards and the challenges' XP are added by whoever knows them. The rules are
## `XpRules`. Reads no node and no clock.

var player_id := 0

var _hundredths := 0


func _init(p_player_id: int = 0) -> void:
	player_id = p_player_id


## Adds what one tally change is worth, when it is this player's. Answers the hundredths added.
func observe(change: Dictionary) -> int:
	if int(change["player_id"]) != player_id:
		return 0
	var added := XpRules.live(change)
	_hundredths += added
	return added


## Adds whole XP that no stat shows: a challenge's reward, the opening night, the day's first game.
func add_xp(xp: int) -> void:
	_hundredths += maxi(xp, 0) * XpRules.HUNDREDTHS


## The running total in hundredths, before the night's cap.
func hundredths() -> int:
	return _hundredths


## Whole XP so far, held to the night's cap.
func xp() -> int:
	return XpRules.to_xp(_hundredths)


## True when the night's cap is reached: more play this night pays nothing.
func capped() -> bool:
	return _hundredths >= XpRules.NIGHT_CAP * XpRules.HUNDREDTHS
