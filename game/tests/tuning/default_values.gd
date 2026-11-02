class_name DefaultValues
extends RefCounted
## The numbers the game shipped with before they became resources you edit (#415): one table per
## resource, read by `test_tuning_defaults.gd`. After you retune on purpose, change the number here
## too: the failing test names the resource and the property, and this is the one place to edit.

const ZOMBIE_TUNING := {
	"hard_cap": 40,
	"repath_interval": 0.25,
	"repath_far_distance": 14.0,
	"repath_far_factor": 2.0,
	"retarget_interval": 0.5,
	"retarget_margin": 2.0,
	"waypoint_reach": 0.4,
	"lure_gather_distance": 2.5,
	"lure_breaks_swings": false,
	"lure_pulls_gate_zombies": false,
	"lure_pulls_bosses": false,
	"separation_radius": 0.8,
	"separation_speed": 2.0,
	"separation_max_speed": 4.0,
	"turn_rate": 9.0,
	"board_stop": 0.9,
	"board_slack": 0.25,
	"reach": 1.4,
	"windup_seconds": 0.45,
	"swing_seconds": 1.2,
	"strike_slack": 0.4,
	"strike_damage": 20.0,
	"emerge_seconds": 0.7,
	"stagger_seconds": 0.4,
	"boss_entrance_seconds": 2.75,
	"boss_stagger_seconds": 1.42,
	"boss_stagger_cooldown": 6.0,
	"push_max_speed": 8.0,
	"push_decay": 14.0,
	"death_seconds": 2.5,
}

const AIM_ASSIST_TUNING := {
	"reach": 30.0,
	"front_cos": 0.5,
	"aim_height": 1.2,
	"capture_metres": 1.1,
	"capture_floor": 0.4,
	"friction_max": 0.6,
	"magnetism_gain": 5.0,
	"magnetism_max_rate": 0.9,
	"flick_speed": 2.0,
	"auto_fire_reach": 25.0,
	"accuracy_gain": 0.39,
	"accuracy_curve": 1.8,
}

## The constants of `ImpactFx`, `ProjectileView` and `LureView`.
const SHOT_FX_TUNING := {
	"spark_size": 0.09,
	"spark_frames": 2,
	"dust_from": 0.09,
	"dust_to": 0.2,
	"mark_size": 0.045,
	"blood_from": 0.06,
	"blood_to": 0.14,
	"lift": 0.04,
	"dust_seconds": 0.28,
	"mark_seconds": 0.8,
	"blood_seconds": 0.22,
	"dust_colour": Color(0.62, 0.58, 0.5),
	"dust_light_colour": Color(0.82, 0.78, 0.68),
	"mark_colour": Color(0.1, 0.085, 0.08, 0.85),
	"blood_colour": Color(0.42, 0.03, 0.05),
	"blood_light_colour": Color(0.68, 0.1, 0.1),
	"flare_core_scale": 1.3,
	"flare_halo_scale": 3.5,
	"flare_halo_alpha": 0.28,
	"flare_core_colour": Color(1.0, 0.82, 0.55),
	"flare_halo_colour": Color(1.0, 0.45, 0.18),
	"flare_flicker_depth": 0.3,
	"flare_flicker_rate_a": 31.0,
	"flare_flicker_rate_b": 47.0,
	"flare_trail_every": 2,
	"flare_trail_seconds": 0.5,
	"flare_trail_radius": 0.05,
	"lure_core_radius": 0.14,
	"lure_halo_radius": 0.7,
	"lure_halo_alpha": 0.3,
	"lure_core_colour": Color(1.0, 0.85, 0.6),
	"lure_halo_colour": Color(1.0, 0.4, 0.15),
	"lure_fade_seconds": 1.0,
	"lure_flicker_depth": 0.35,
	"lure_flicker_rate_a": 23.0,
	"lure_flicker_rate_b": 37.0,
	"lure_lift": Vector3(0.0, 0.12, 0.0),
	"lure_ember_count": 12,
	"lure_ember_seconds": 1.4,
	"lure_ember_rise": 2.2,
	"lure_ember_size": 0.05,
}

const SOUND_MIX := {
	"group_limits":
	{
		&"ui": 4,
		&"ui_hint": 1,
		&"challenge": 1,
		&"gun": 12,
		&"reload": 4,
		&"step": 8,
		&"step_own": 2,
		&"zombie_voice": 6,
		&"zombie_boss": 2,
		&"zombie_step": 5,
		&"generator": 2,
		&"grenade": 8,
		&"sting": 1,
		&"board": 4,
		&"door": 2,
		&"melee": 4,
		&"till": 2,
		&"soldier_voice": 3,
		&"bed": 4,
		&"gun_tail": 4,
		&"impact": 6,
		&"swap": 2,
		&"breaker": 2,
		&"shop": 4,
		&"points": 2,
	},
	"voice_db": -4.0,
	"own_voice_db": -2.0,
	"voice_max_distance": 40.0,
	"voice_unit_size": 6.0,
}

## Every sound's values before the banks: `sound_defaults.json`, id to its properties (`near_cap_db`
## "inf" is infinity).
const SOUNDS_PATH := "res://tests/tuning/sound_defaults.json"


## The sound table as a dictionary of id to its property table.
static func sounds() -> Dictionary:
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOUNDS_PATH))
	for id: String in table:
		var row: Dictionary = table[id]
		if row["near_cap_db"] is String:
			row["near_cap_db"] = INF
	return table


## Differences between a resource and its table, one line each; empty when they agree. A property
## the resource exports but the table lacks is a difference too, so a new number is pinned as well.
static func differences(resource: Resource, table: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var exported := {}
	for info in resource.get_property_list():
		if (
			(info["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0
			and (info["usage"] & PROPERTY_USAGE_STORAGE) != 0
		):
			exported[info["name"]] = true
	for key: String in table:
		if not exported.has(key):
			out.append("%s: in the table, not exported" % key)
		elif not _same(resource.get(key), table[key]):
			out.append("%s: file %s, was %s" % [key, resource.get(key), table[key]])
	for key: String in exported:
		if not table.has(key):
			out.append("%s: exported, not in the table" % key)
	return out


static func _same(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for key: Variant in b:
			if not a.has(key) or not _same(a[key], b[key]):
				return false
		return true
	if (a is StringName or a is String) and (b is StringName or b is String):
		return String(a) == String(b)
	if (a is float or a is int) and (b is float or b is int):
		return is_equal_approx(float(a), float(b))
	return a == b
