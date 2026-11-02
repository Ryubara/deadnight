class_name QuickStrike
extends RefCounted
## The quick melee's clips (#411): one blow for every weapon, a clip per class built from the
## class's own aim pose (`Strike_<Class>`, docs/design/animation.md, Quick melee), in a file of its
## own that `PlayerAnimation` adds to the Soldier's library. `PlayerAnimation.strike` plays them.

const GLB := "res://assets/characters/soldier/strike/soldier_strike.glb"
const SPEC := "res://assets/characters/soldier/strike/clips.json"
const CLIPS: Array[StringName] = [
	&"Strike_Rifle", &"Strike_Shotgun", &"Strike_Pistol", &"Strike_Melee"
]
