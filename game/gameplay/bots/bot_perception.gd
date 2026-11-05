class_name BotPerception
extends RefCounted
## The filter between the frame and the brain. A frame lists every zombie in the lot, as it does
## for a person's client; a person sees what is in front of them, inside the light, with nothing
## solid in between, and notices it after a moment. This class lets the bot know the same:
##
## - a zombie is *seen* at a think when it is inside the view cone, inside the sight range (which
##   follows the light) and a ray from the eye reaches its chest or head; at most
##   `BotProfile.rays_per_think` rays, the nearest first;
## - a seen zombie becomes *believed* only after its reaction delay, drawn per contact (a
##   log-normal around the profile's mean, never under `BotProfile.REACTION_FLOOR`);
## - a believed zombie that is no longer seen is *remembered* for the memory time, then forgotten;
##   it is never shot at while it is only remembered;
## - a zombie out of sight and near is *heard*: a direction and a range class, never a position;
## - a zombie swinging at the bot from within arm's reach (`ARM_REACH`) is felt whichever way the
##   bot faces, when the bot has no target in view: it counts as seen (its reaction time runs once,
##   not again at every think).
##
## The brain gets the `BotBeliefs` and nothing else. All randomness is the bot's own seeded stream.

## Seconds over which the speed of a contact is averaged (positions come in whole centimetres).
const VELOCITY_WINDOW := 0.25
## Radians of error, one sigma, in the direction of a sound.
const HEARING_ERROR := 0.15
## Seconds a landed blow's direction is kept.
const BLOW_MEMORY := 2.0
## Longest a reaction may be, in means.
const REACTION_CEILING := 3.0
## Metres within which a zombie in its swing is noticed from any side by a bot with no target in
## view: it is being hit and has nobody else to fight. (Out of the cone the zombie was dropped at
## every think and its reaction began again, so three dead around a bot that looked away were
## never believed in. A bot with a target in front keeps to it, as before.)
const ARM_REACH := 2.0

var beliefs := BotBeliefs.new()
## Rays cast in the last think, and in all.
var rays_last := 0
var rays_total := 0

var _profile: BotProfile
var _level: BotLevel
var _rng: RandomNumberGenerator


func _init(profile: BotProfile, level: BotLevel, rng: RandomNumberGenerator) -> void:
	_profile = profile
	_level = level
	_rng = rng


## Seconds from the first clear ray on a zombie to the bot believing in it.
func draw_reaction() -> float:
	var spread := _profile.reaction_spread
	var sigma := sqrt(log(1.0 + spread * spread))
	var mu := log(_profile.reaction_seconds) - 0.5 * sigma * sigma
	var seconds := exp(mu + sigma * _rng.randfn())
	return clampf(seconds, BotProfile.REACTION_FLOOR, _profile.reaction_seconds * REACTION_CEILING)


## A blow landed on the bot, from `yaw` (a view yaw to look toward it).
func hear_blow(yaw: float) -> void:
	beliefs.blows.append({"yaw": yaw, "at": beliefs.now})


## One tick. `think` is true on the ticks the bot looks properly (casts rays); on the others it
## only keeps the contacts it has in sight up to date. `view_yaw` is where the bot looks.
func observe(
	now: float,
	think: bool,
	me: Dictionary,
	zombies: Array[Dictionary],
	round_number: int,
	view_yaw: float
) -> void:
	beliefs.now = now
	if think and not beliefs.blows.is_empty():
		beliefs.blows.assign(
			beliefs.blows.filter(
				func(blow: Dictionary) -> bool: return now - blow["at"] <= BLOW_MEMORY
			)
		)
	if beliefs.contacts.is_empty() and not think:
		return
	var here: Vector3 = me.get("pos", Vector3.ZERO)
	# The zombies of the frame that the bot holds a contact on, by id: the bot reads no other (the
	# crowd is a hundred, its contacts a handful).
	var by_id := {}
	if not beliefs.contacts.is_empty():
		var contacts := beliefs.contacts
		for zombie in zombies:
			var id: int = zombie["id"]
			if contacts.has(id):
				by_id[id] = zombie
		_drop_gone(by_id)
	if think:
		_look(zombies, here, round_number, view_yaw)
	else:
		_follow(by_id)
	_expire()


# --- A proper look ---


func _look(zombies: Array[Dictionary], here: Vector3, round_number: int, view_yaw: float) -> void:
	rays_last = 0
	beliefs.heard = []
	var eye := here + Vector3(0.0, BotLevel.EYE_HEIGHT, 0.0)
	var cos_half := cos(deg_to_rad(_profile.view_degrees) * 0.5)
	var forward := Vector2(-sin(view_yaw), -cos(view_yaw))
	# Nearest first, as (distance, index into `zombies`) pairs: sorted by the engine, not a lambda.
	var candidates: Array[Vector2] = []
	# The cheap tests first: how far, and where in the view. The light is asked about only for
	# the ones that pass, nearest first, and only until the rays are spent. One that is out of the
	# view or too far is plainly not seen (and heard, if it is near).
	for index in zombies.size():
		var zombie := zombies[index]
		if not _on_foot(zombie):
			continue
		var at: Vector3 = zombie["position"]
		var offset := Vector2(at.x - here.x, at.z - here.z)
		var flat := offset.length()
		if flat <= BotLevel.MAX_VIEW and forward.dot(offset) >= cos_half * flat:
			candidates.append(Vector2(flat, float(index)))
			continue
		if flat <= ARM_REACH and zombie["mode"] == ZombieBody.Mode.ATTACK and _no_target(here):
			_sighted(zombie)
			continue
		_lost(zombie["id"])
		if flat <= _profile.hearing_range:
			_hear(zombie, here, flat)
	candidates.sort()
	for pair in candidates:
		if rays_last >= _profile.rays_per_think:
			break
		var zombie := zombies[int(pair.y)]
		if pair.x <= _level.view_range(zombie["position"], round_number) and _sees(eye, zombie):
			_sighted(zombie)
			continue
		_lost(zombie["id"])
		if pair.x <= _profile.hearing_range:
			_hear(zombie, here, pair.x)
	rays_total += rays_last


## Whether nothing is believed and in view as it stands (before this look's sightings).
func _no_target(here: Vector3) -> bool:
	return beliefs.targets(here).is_empty()


## A ray from the eye reaches the chest, else the head.
func _sees(eye: Vector3, zombie: Dictionary) -> bool:
	var look: StringName = zombie.get("look", ZombieModels.DEFAULT)
	var mode: int = zombie.get("mode", ZombieBody.Mode.CHASE)
	var yaw := float(zombie.get("yaw", 0.0))
	var climbing: bool = zombie.get("climbing", false)
	var base: Vector3 = zombie["position"]
	rays_last += 1
	if _level.clear(eye, base + ZombiePose.aim_offset(look, mode, yaw, Hitbox.BODY, climbing)):
		return true
	if rays_last >= _profile.rays_per_think:
		return false
	rays_last += 1
	return _level.clear(eye, base + ZombiePose.aim_offset(look, mode, yaw, Hitbox.HEAD, climbing))


func _sighted(zombie: Dictionary) -> void:
	var id: int = zombie["id"]
	var contact: Dictionary = beliefs.contacts.get(id, {})
	if contact.is_empty():
		beliefs.contact_seq += 1
		beliefs.contacts[id] = {
			"id": id,
			"position": zombie["position"],
			"velocity": Vector3.ZERO,
			"look": zombie.get("look", ZombieModels.DEFAULT),
			"mode": zombie["mode"],
			"climbing": zombie.get("climbing", false),
			"status": zombie.get("status", 0),
			"yaw": zombie.get("yaw", 0.0),
			"episode": zombie.get("episode", 0),
			"attack_at": beliefs.now if zombie["mode"] == ZombieBody.Mode.ATTACK else -1.0,
			"first_seen": beliefs.now,
			"last_seen": beliefs.now,
			"believed_at": beliefs.now + draw_reaction(),
			"visible": true,
			"anchor_pos": zombie["position"],
			"anchor_at": beliefs.now,
		}
		return
	_update(contact, zombie)
	contact["visible"] = true


## The contact is out of sight: a believed one is remembered, one still in its reaction time is
## dropped (it was never noticed).
func _lost(id: int) -> void:
	var contact: Dictionary = beliefs.contacts.get(id, {})
	if contact.is_empty():
		return
	if beliefs.is_believed(contact):
		contact["visible"] = false
	else:
		beliefs.contacts.erase(id)


func _hear(zombie: Dictionary, here: Vector3, flat: float) -> void:
	var offset: Vector3 = zombie["position"] - here
	(
		beliefs
		. heard
		. append(
			{
				"yaw": atan2(-offset.x, -offset.z) + _rng.randfn(0.0, HEARING_ERROR),
				"range_class":
				BotBeliefs.VERY_NEAR if flat <= _profile.hearing_range * 0.5 else BotBeliefs.NEAR,
				"at": beliefs.now,
			}
		)
	)


# --- Between looks ---


## The contacts in sight move with their zombies; nothing is looked at.
func _follow(by_id: Dictionary) -> void:
	for id in beliefs.contacts:
		var contact: Dictionary = beliefs.contacts[id]
		if contact["visible"] and by_id.has(id):
			_update(contact, by_id[id])


func _update(contact: Dictionary, zombie: Dictionary) -> void:
	contact["position"] = zombie["position"]
	contact["yaw"] = zombie.get("yaw", contact.get("yaw", 0.0))
	_note_swing(contact, zombie)
	contact["mode"] = zombie["mode"]
	contact["status"] = zombie.get("status", 0)
	contact["last_seen"] = beliefs.now
	var gap: float = beliefs.now - contact["anchor_at"]
	if gap >= VELOCITY_WINDOW:
		var moved: Vector3 = zombie["position"] - contact["anchor_pos"]
		contact["velocity"] = Vector3(moved.x, 0.0, moved.z) / gap
		contact["anchor_pos"] = zombie["position"]
		contact["anchor_at"] = beliefs.now


## A swing is first seen on the clock: the telegraph the bot reacts to. A new swing (the episode
## counter moved, or the mode just became an attack) starts the clock again; any other mode ends it.
func _note_swing(contact: Dictionary, zombie: Dictionary) -> void:
	var episode: int = zombie.get("episode", 0)
	if zombie["mode"] != ZombieBody.Mode.ATTACK:
		contact["attack_at"] = -1.0
	elif contact["mode"] != ZombieBody.Mode.ATTACK or episode != contact.get("episode", 0):
		contact["attack_at"] = beliefs.now
	contact["episode"] = episode


## A zombie that left the frame (killed, gone) leaves the beliefs; so does one that is going
## down, which nobody shoots at.
func _drop_gone(by_id: Dictionary) -> void:
	for id in beliefs.contacts.keys():
		if not by_id.has(id) or not _on_foot(by_id[id]):
			beliefs.contacts.erase(id)


func _expire() -> void:
	for id in beliefs.contacts.keys():
		var contact: Dictionary = beliefs.contacts[id]
		if (
			not contact["visible"]
			and beliefs.now - float(contact["last_seen"]) > _profile.memory_seconds
		):
			beliefs.contacts.erase(id)


## Up and about: neither coming out of the ground nor on the way down.
static func _on_foot(zombie: Dictionary) -> bool:
	return zombie["mode"] != ZombieBody.Mode.DYING and zombie["mode"] != ZombieBody.Mode.EMERGING
