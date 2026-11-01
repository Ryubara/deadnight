class_name VoiceBudget
extends RefCounted
## Decides which sounds get one of a fixed number of voice slots (the service owns one player per
## slot).
##
## A request is dropped if its sound started too recently (cooldown). Otherwise it needs a slot:
## a free one, or one taken from a weaker voice. A group that is at its limit may only replace
## its own weakest voice, and only with something stronger: a higher priority, or the same
## priority and clearly louder (nearer). No engine nodes and no clock of its own: time is passed
## in, so tests run it at any speed.

## A new sound must beat a same-priority voice's loudness by this factor to take its slot.
const LOUDER_BY := 1.15

var slot_count: int
var group_limits: Dictionary
## Counters for tests and the debug overlay.
var stolen := 0
var rejected := 0

var _voices: Array[Voice] = []
var _last_start := {}


class Voice:
	extends RefCounted
	var sound: StringName
	var group: StringName
	var priority: int
	var loudness: float
	var started: float
	var ends: float


func _init(slots: int, limits: Dictionary = {}) -> void:
	slot_count = slots
	group_limits = limits
	_voices.resize(slots)


## A slot for this sound, or -1 when it should not play. The caller starts its player on that slot.
func acquire(def: SoundDef, loudness: float, now: float, duration: float) -> int:
	expire(now)
	if def.cooldown > 0.0 and now - float(_last_start.get(def.id, -INF)) < def.cooldown:
		rejected += 1
		return -1
	var limit: int = group_limits.get(def.group, slot_count)
	var in_group := _slots_in_group(def.group)
	var slot := -1
	if in_group.size() >= limit:
		slot = _weakest(in_group)
	else:
		slot = _voices.find(null)
		if slot < 0:
			slot = _weakest(_occupied())
	if _voices[slot] != null:
		if not _beats(_voices[slot], def.priority, loudness):
			rejected += 1
			return -1
		stolen += 1
	var voice := Voice.new()
	voice.sound = def.id
	voice.group = def.group
	voice.priority = def.priority
	voice.loudness = loudness
	voice.started = now
	voice.ends = now + duration
	_voices[slot] = voice
	_last_start[def.id] = now
	return slot


## Frees every slot whose sound has finished by `now`.
func expire(now: float) -> void:
	for i in _voices.size():
		if _voices[i] != null and _voices[i].ends <= now:
			_voices[i] = null


func release(slot: int) -> void:
	_voices[slot] = null


func release_all() -> void:
	_voices.fill(null)
	_last_start.clear()


func active_count() -> int:
	return _voices.size() - _voices.count(null)


func group_count(group: StringName) -> int:
	return _slots_in_group(group).size()


func sound_at(slot: int) -> StringName:
	return &"" if _voices[slot] == null else _voices[slot].sound


func loudness_at(slot: int) -> float:
	return 0.0 if _voices[slot] == null else _voices[slot].loudness


func is_active(slot: int) -> bool:
	return _voices[slot] != null


func _occupied() -> Array[int]:
	var found: Array[int] = []
	for i in _voices.size():
		if _voices[i] != null:
			found.append(i)
	return found


func _slots_in_group(group: StringName) -> Array[int]:
	var found: Array[int] = []
	for i in _voices.size():
		if _voices[i] != null and _voices[i].group == group:
			found.append(i)
	return found


## The slot (of those given) holding the least important voice: lowest priority, then quietest,
## then oldest.
func _weakest(slots: Array[int]) -> int:
	var best := slots[0]
	for slot in slots:
		var a := _voices[slot]
		var b := _voices[best]
		if a.priority != b.priority:
			if a.priority < b.priority:
				best = slot
		elif a.loudness != b.loudness:
			if a.loudness < b.loudness:
				best = slot
		elif a.started < b.started:
			best = slot
	return best


## Whether a new sound may take the voice's slot.
func _beats(voice: Voice, priority: int, loudness: float) -> bool:
	if priority != voice.priority:
		return priority > voice.priority
	return loudness > voice.loudness * LOUDER_BY
