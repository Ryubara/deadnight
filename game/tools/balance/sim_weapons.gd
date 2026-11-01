class_name SimWeapons
extends RefCounted
## What the modelled players shoot. The rules do not own weapons (the weapon work does), so the
## simulator carries a stand-in table: damage per landed shot and shots per second, sustained
## (reloading included). Replace the numbers with the real weapon data when it exists; the report
## says which table it used.

const ZONE_MULTIPLIER := {&"head": 2.0, &"body": 1.0, &"limb": 0.75, &"weak": 1.0}

## id -> [damage, shots per second]
const TABLE := {
	&"pistol": [28.0, 3.0],
	&"weapon_shotgun": [95.0, 1.3],
	&"weapon_rifle": [50.0, 4.2],
	&"weapon_smg": [22.0, 8.0],
	&"weapon_flare_gun": [160.0, 0.7],
}
const START := &"pistol"


static func damage(weapon_id: StringName) -> float:
	return TABLE[weapon_id][0]


static func rate(weapon_id: StringName) -> float:
	return TABLE[weapon_id][1]


## The best weapon among those owned, by damage per second.
static func best(owned: Array[StringName]) -> StringName:
	var best_id := START
	var best_dps := damage(START) * rate(START)
	for weapon_id in owned:
		if not TABLE.has(weapon_id):
			continue
		var dps := damage(weapon_id) * rate(weapon_id)
		if dps > best_dps:
			best_dps = dps
			best_id = weapon_id
	return best_id
