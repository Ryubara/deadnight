class_name SoundSchedule
extends RefCounted
## Things to do a little later, on a clock the owner moves (`advance`), never the wall clock: a
## gun's tail a few hundredths after its report, a reload's steps on the frames of its clip. A
## test steps it by hand and a recording steps it with the frames, so the same night always
## sounds the same.

var _items: Array[Dictionary] = []
var _now := 0.0
## While an item runs, new items count from its own time, so a chain (a grenade's ticks) does not
## drift with the size of the step that ran it.
var _base := -1.0


## Runs `action` `delay` seconds from now. `tag` lets `cancel` drop it.
func add(delay: float, action: Callable, tag: StringName = &"") -> void:
	var from := _base if _base >= 0.0 else _now
	_items.append({"at": from + maxf(delay, 0.0), "action": action, "tag": tag})


## Drops every waiting item with this tag; returns how many.
func cancel(tag: StringName) -> int:
	var before := _items.size()
	_items = _items.filter(func(item: Dictionary) -> bool: return item["tag"] != tag)
	return before - _items.size()


func advance(delta: float) -> void:
	_now += delta
	while true:
		var next := -1
		for i in _items.size():
			if _items[i]["at"] <= _now and (next < 0 or _items[i]["at"] < _items[next]["at"]):
				next = i
		if next < 0:
			break
		var item: Dictionary = _items.pop_at(next)
		_base = item["at"]
		(item["action"] as Callable).call()
		_base = -1.0


func pending() -> int:
	return _items.size()


## The clock now; inside a running item, the time that item was due, so a sound it starts is
## stamped with the moment it belongs to and not with the end of the step that ran it.
func now() -> float:
	return _base if _base >= 0.0 else _now


func clear() -> void:
	_items.clear()
