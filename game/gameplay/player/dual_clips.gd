class_name DualClips
extends RefCounted
## The dual pistols' arm clips (#789): the Pistol clips with the left arm doing what the right does,
## mirrored, so a pistol rises, kicks, swings and bashes in each hand. One file of their own,
## `dual/soldier_dual.glb` with its `clips.json`, that `PlayerAnimation` adds to the Soldier's
## library (`docs/design/animation.md`, Dual pistols). The aim and the fire are the hands' IK's
## while a weapon is up, so these are what the arms do around it: equip, unequip, the sprint and
## the quick melee, and the pose the IK blends from.

const GLB := "res://assets/characters/soldier/dual/soldier_dual.glb"
const SPEC := "res://assets/characters/soldier/dual/clips.json"
const CLASS := &"Dual"
const CLIPS: Array[StringName] = [
	&"Aim_Dual", &"Fire_Dual", &"Equip_Dual", &"Unequip_Dual", &"Strike_Dual", &"Sprint_Dual"
]
