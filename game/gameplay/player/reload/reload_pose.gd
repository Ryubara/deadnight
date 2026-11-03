class_name ReloadPose
extends RefCounted
## A reload's pose at one moment (`ReloadMotion.sample`), eased between its two keys: what
## `WeaponHandsIK` adds to the hold and what `PlayerAnimation` does to the part and the ammunition.

var motion: ReloadMotion
var weapon_offset := Vector3.ZERO
var weapon_turn := Vector3.ZERO
var chest_lean := 0.0
var chest_turn := 0.0
var part := 0.0
var part_shown := true
var ammo := false
## How far the left hand is on the reload's point (0: the hold's own).
var left := 0.0
## The two keys whose points the hand travels between, and how far it is (null: no point).
var left_from: ReloadKey
var left_to: ReloadKey
var left_mix := 0.0


func clear() -> void:
	weapon_offset = Vector3.ZERO
	weapon_turn = Vector3.ZERO
	chest_lean = 0.0
	chest_turn = 0.0
	part = 0.0
	part_shown = true
	ammo = false
	left = 0.0
	left_from = null
	left_to = null
	left_mix = 0.0
