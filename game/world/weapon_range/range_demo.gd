class_name RangeDemo
extends RefCounted
## The scripted tour of the test range, one list of timed steps `{at, do}` that `WeaponRange` runs
## on its fixed step. It shows each weapon once: the rifle through two zombies, a pistol headshot,
## the SMG, melee, the shotgun, a shot the corner stops and the same shot from beside the corner
## that lands, and the flare. Zombie slots are in `WeaponRange.SLOTS`.

const START := 1.0
const BURST_SHOTS := 5
const BURST_GAP := 0.1


static func steps() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	_at(list, START, func(r: WeaponRange) -> void: r.give(&"rifle"))
	_at(list, START + 0.6, func(r: WeaponRange) -> void: r.fire_at(_chest(r, 0)))
	_at(list, START + 1.4, func(r: WeaponRange) -> void: r.give(&"pistol"))
	_at(list, START + 2.0, func(r: WeaponRange) -> void: r.fire_at(_head(r, 1)))
	_at(list, START + 3.0, func(r: WeaponRange) -> void: r.give(&"smg"))
	for i in BURST_SHOTS:
		_at(
			list, START + 3.4 + i * BURST_GAP, func(r: WeaponRange) -> void: r.fire_at(_chest(r, 3))
		)
	_at(list, START + 5.0, func(r: WeaponRange) -> void: r.give(&"crowbar"))
	_at(list, START + 5.4, func(r: WeaponRange) -> void: r.swing_at(_chest(r, 2)))
	_at(list, START + 6.2, func(r: WeaponRange) -> void: r.swing_at(_chest(r, 2)))
	_at(list, START + 7.3, func(r: WeaponRange) -> void: r.give(&"shotgun"))
	_at(list, START + 7.8, func(r: WeaponRange) -> void: r.fire_at(_chest(r, 5)))
	_at(list, START + 9.0, func(r: WeaponRange) -> void: r.fire_at(_chest(r, 5)))
	_at(list, START + 10.5, func(r: WeaponRange) -> void: r.give(&"pistol"))
	_at(list, START + 11.0, func(r: WeaponRange) -> void: r.fire_at(_chest(r, 4)))
	_at(list, START + 11.6, func(r: WeaponRange) -> void: r.fire_at(_chest(r, 4)))
	_at(list, START + 12.5, func(r: WeaponRange) -> void: r.move_rig(Vector3(1.6, 0, 0)))
	_at(list, START + 13.2, func(r: WeaponRange) -> void: r.fire_at(_chest(r, 4)))
	_at(list, START + 14.2, func(r: WeaponRange) -> void: r.give(&"flare_gun"))
	_at(list, START + 14.8, func(r: WeaponRange) -> void: r.fire_at(_chest(r, 4)))
	return list


static func length() -> float:
	var list := steps()
	return list[list.size() - 1]["at"]


static func _at(list: Array[Dictionary], at: float, action: Callable) -> void:
	list.append({"at": at, "do": action})


static func _chest(r: WeaponRange, slot: int) -> Vector3:
	return r.zombie_position(slot) + Vector3(0, WeaponRange.BODY_HEIGHT, 0)


static func _head(r: WeaponRange, slot: int) -> Vector3:
	return r.zombie_position(slot) + Vector3(0, WeaponRange.HEAD_HEIGHT, 0)
