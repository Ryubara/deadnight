class_name BotFightBrain
extends BotBrain
## The brain of phase 1: the fight and nothing else (the errands, the follow, the revive and the
## real movement come with the later phases). It shoots the nearest believed zombie in sight and
## keeps to it while it stays a fair choice, backs away from anything that gets inside the
## profile's margin, looks toward a blow it felt or a sound it heard, reloads when the magazine is
## dry or low in a quiet moment, and swaps to a weapon that has rounds when its own is spent.

## Metres a committed target may be farther than the nearest before the bot changes its mind.
const COMMITMENT := 3.0
## Metres from a zombie inside which a tactical reload waits.
const RELOAD_SAFE := 8.0
## Share of a magazine under which a quiet moment is used to reload.
const LOW_MAGAZINE := 0.3
## Ticks between two swaps.
const SWAP_EVERY := 20
## How much of the way home bends a retreat (so it circles the field, not a corner).
const HOME_BEND := 0.35

var _profile: BotProfile
var _level: BotLevel
var _committed := -1
var _thinks := 0
var _swapped_at := -SWAP_EVERY


func _init(profile: BotProfile, level: BotLevel) -> void:
	_profile = profile
	_level = level


func think(beliefs: BotBeliefs, state: ClientState) -> BotIntent:
	_thinks += 1
	var intent := BotIntent.new()
	var me := state.me()
	if me.is_empty() or me.get("downed", true):
		return intent
	var here: Vector3 = me["pos"]
	var held := _held(me)
	var targets := beliefs.targets(here)
	intent.target_id = _choose(targets, here)
	_committed = intent.target_id
	var threat := beliefs.nearest_threat(here, _profile.memory_seconds)
	if threat < _profile.retreat_margin and (held == null or not held.is_melee()):
		intent.wish = _retreat(here, beliefs)
		intent.sprint = true
		intent.note = "retreat"
	if intent.target_id < 0:
		intent.look_yaw = _glance(beliefs, here)
	_handle_weapon(intent, me, held, threat)
	if intent.note == "":
		intent.note = "fight" if intent.target_id >= 0 else "hold"
	return intent


## The target to shoot: the nearest in sight, kept once chosen unless another is clearly nearer.
func _choose(targets: Array[Dictionary], here: Vector3) -> int:
	var best := -1
	var best_score := INF
	for contact in targets:
		var score := (
			Vector2(contact["position"].x - here.x, contact["position"].z - here.z).length()
		)
		if contact["id"] == _committed:
			score -= COMMITMENT
		if score < best_score:
			best_score = score
			best = contact["id"]
	return best


## Away from the nearest thing it knows of, bent toward home.
func _retreat(here: Vector3, beliefs: BotBeliefs) -> Vector3:
	var from := Vector3.INF
	var best := INF
	for id in beliefs.contacts:
		var contact: Dictionary = beliefs.contacts[id]
		if not beliefs.is_believed(contact):
			continue
		var at := beliefs.guess(contact, _profile.memory_seconds)
		var apart := Vector2(at.x - here.x, at.z - here.z).length()
		if apart < best:
			best = apart
			from = at
	if from == Vector3.INF:
		return Vector3.ZERO
	var away := here - from
	away.y = 0.0
	var bent := away.normalized()
	if _level.home != Vector3.INF:
		var home := _level.home - here
		home.y = 0.0
		bent = (bent + home.normalized() * HOME_BEND).normalized()
	return bent


## Where to turn when nothing is in sight: a blow, else a sound, else a remembered zombie.
func _glance(beliefs: BotBeliefs, here: Vector3) -> float:
	if not beliefs.blows.is_empty():
		return beliefs.blows.back()["yaw"]
	if not beliefs.heard.is_empty():
		return beliefs.heard[0]["yaw"]
	for contact in beliefs.remembered():
		var at := beliefs.guess(contact, _profile.memory_seconds) - here
		return atan2(-at.x, -at.z)
	return NAN


func _handle_weapon(intent: BotIntent, me: Dictionary, held: WeaponDef, threat: float) -> void:
	if held == null:
		return
	var reloading: bool = me.get("reloading", false)
	var ammo: int = me.get("ammo", 0)
	var reserve: int = me.get("reserve", 0)
	if not held.is_melee() and not reloading and reserve > 0:
		var dry := ammo <= 0
		var low := float(ammo) < float(held.magazine_size) * LOW_MAGAZINE
		intent.reload = dry or (low and threat > RELOAD_SAFE)
	if _thinks - _swapped_at >= SWAP_EVERY and _wants_swap(me, held):
		intent.swap = true
		_swapped_at = _thinks


## Swap away from a melee weapon or an empty gun to one that has rounds; from an empty gun to the
## melee weapon when nothing else can shoot.
func _wants_swap(me: Dictionary, held: WeaponDef) -> bool:
	var arms: Dictionary = me.get("arms", {})
	if arms.size() < 2:
		return false
	if not held.is_melee() and _rounds(arms, held.id) > 0:
		return false
	var other_has_rounds := false
	for id: StringName in arms:
		if id != held.id and not WeaponCatalog.get_def(id).is_melee() and _rounds(arms, id) > 0:
			other_has_rounds = true
	return other_has_rounds if held.is_melee() else true


static func _rounds(arms: Dictionary, weapon_id: StringName) -> int:
	var counts: Array = arms.get(weapon_id, [0, 0])
	return int(counts[0]) + int(counts[1])


static func _held(me: Dictionary) -> WeaponDef:
	var id: StringName = me.get("weapon", &"")
	return WeaponCatalog.get_def(id) if id != &"" else null
