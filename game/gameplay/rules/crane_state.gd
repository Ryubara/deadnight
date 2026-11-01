class_name CraneState
extends RefCounted
## What the rules know about the prize crane: where it stands, how many plays it has had there, and
## the play in progress. Plain data; GameRules is the only thing that changes it.

enum Stage { READY, SPIN, GRAB, LEAVING }

## The keys of `to_dict`, each with the type it must have.
const SNAPSHOT_KEYS := {
	"spot": TYPE_INT,
	"plays": TYPE_INT,
	"stage": TYPE_INT,
	"buyer_id": TYPE_INT,
	"price": TYPE_INT,
	"breaks": TYPE_BOOL,
	"weapon": TYPE_STRING,
	"left": TYPE_FLOAT,
}

var spot: int = 0
## Plays since the crane arrived at `spot`.
var plays: int = 0
var stage: Stage = Stage.READY
## The player whose play is running (-1 when none).
var buyer_id: int = -1
## What the play cost, for the refund.
var price: int = 0
## Whether the running play ends in a breakdown (decided when it is bought).
var breaks: bool = false
## The prize floating for the buyer (GRAB only).
var weapon: StringName = &""
## Seconds left in this stage.
var left: float = 0.0


func _init(p_spot: int = 0) -> void:
	spot = p_spot


func is_ready() -> bool:
	return stage == Stage.READY


func to_dict() -> Dictionary:
	return {
		"spot": spot,
		"plays": plays,
		"stage": stage,
		"buyer_id": buyer_id,
		"price": price,
		"breaks": breaks,
		"weapon": String(weapon),
		"left": left,
	}


## True when `data` has the keys and sane values; changes nothing.
func fits(data: Dictionary, count: int) -> bool:
	return (
		SnapshotCheck.fits(data, SNAPSHOT_KEYS)
		and data["spot"] >= 0
		and data["spot"] < count
		and data["plays"] >= 0
		and data["stage"] >= 0
		and data["stage"] < Stage.size()
		and is_finite(data["left"])
	)


func restore(data: Dictionary) -> void:
	spot = data["spot"]
	plays = data["plays"]
	stage = data["stage"]
	buyer_id = data["buyer_id"]
	price = data["price"]
	breaks = data["breaks"]
	weapon = StringName(data["weapon"])
	left = data["left"]
