class_name DefaultValues
extends RefCounted
## The numbers the game shipped with before they became resources you edit (#415): one table per
## resource, read by `test_tuning_defaults.gd`. After you retune on purpose, change the number here
## too: the failing test names the resource and the property, and this is the one place to edit.

const ZOMBIE_TUNING := {
	"hard_cap": 40,
	"mark_last": 3,
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

## The constants of `FootstepSounds`, `WeaponSounds`, `GrenadeSounds`, `WorldSounds`,
## `ZombieVoices`, `VoiceDirector` and `SoldierVoice`.
const NIGHT_SOUND_TUNING := {
	"step_pace": 4.8,
	"step_sprint_pace": 7.0,
	"step_db_per_decade": 25.0,
	"step_min_db": -18.0,
	"step_max_db": 5.0,
	"step_crouch_db": -4.0,
	"step_jitter_db": 1.5,
	"remote_step_distance": 1.9,
	"tail_delay": 0.03,
	"tail_spread": 0.02,
	"shot_jitter_db": 0.5,
	"max_world_impacts": 3,
	"hit_match_radius": 1.5,
	"range_margin": 0.5,
	"tick_gap_start": 0.5,
	"tick_gap_end": 0.1,
	"bounce_quiet_db": -9.0,
	"bounce_loud_db": 0.0,
	"bounce_fast_speed": 12.0,
	"hum_idle_db": -15.0,
	"hum_full_db": -7.0,
	"engine_idle_db": -22.0,
	"engine_full_db": -9.0,
	"hum_idle_pitch": 0.94,
	"hum_full_pitch": 1.05,
	"starve_wobble": 0.035,
	"starve_wobble_hz": 6.0,
	"slew_db_per_s": 24.0,
	"off_db": -60.0,
	"sputter_gap_low": 4.0,
	"sputter_gap_dry": 1.0,
	"bed_delay": 2.4,
	"buy_gap": 0.2,
	"prize_ding_delay": 0.35,
	"alert_range": 22.0,
	"idle_range": 36.0,
	"step_range": 28.0,
	"idle_gap_min": 0.6,
	"idle_gap_max": 1.6,
	"idle_self_min": 5.0,
	"idle_self_max": 11.0,
	"idle_pool": 3,
	"alert_gap": 0.35,
	"hurt_gap": 0.4,
	"swing_repeat": 1.2,
	"boss_death_db": -8.0,
	"line_gap": 0.5,
	"interrupt_priority": 80,
	"cut_margin": 25,
	"remember_takes": 3,
	"streak_kills": 4,
	"streak_window": 6.0,
	"low_health": 0.35,
	"big_buy": 1000,
	"low_magazine": 0.4,
	"round_start_delay": 1.6,
	"round_clear_delay": 2.4,
	"boss_delay": 0.8,
	"rescue_delay": 0.4,
	"idle_after": 5.0,
	"idle_margin": 8.0,
	"lull": 10.0,
	"lull_distance": 30.0,
}

## The constants of `LotLamps`, `NightLight` and the lot's fixtures.
const LIGHT_TUNING := {
	"lamp_reach": 6.0,
	"flicker_ticks": 5,
	"sag_floor": 0.35,
	"dropout": 0.12,
	"ease_seconds": 12.0,
	"darkest_ambient": 0.35,
	"darkest_moon": 0.5,
	"darkest_sky": 0.5,
	"darkest_fog_density": 1.7,
	"bulb_dark_albedo": 0.25,
	"bulb_energy": 3.0,
	"bulb_halo_energy": 0.9,
	"bulb_pool_energy": 0.5,
	"switch_glow_off": 0.5,
	"switch_glow_on": 2.0,
	"switch_halo_on": 1.1,
	"switch_halo_off": 0.45,
	"neon_tube_energy": 3.0,
	"neon_halo_energy": 0.9,
	"screen_face_energy": 1.0,
	"screen_spill_energy": 0.1,
	"pane_energy": 0.55,
	"beam_energy": 0.14,
	"beam_halo_energy": 1.5,
	"beam_near": 1.0,
	"beam_far": 0.12,
}

## The soldier's moments before `soldier_moments_default.tres` (`SoldierVoiceCatalog.EVENTS`):
## event, takes, priority, cooldown, chance.
const SOLDIER_MOMENTS := [
	[&"downed", 4, 100, 0.0, 1.0],
	[&"hurt", 8, 90, 1.6, 0.85],
	[&"boss_arrive", 5, 75, 20.0, 1.0],
	[&"boss_dead", 4, 72, 20.0, 1.0],
	[&"close_call", 5, 70, 14.0, 1.0],
	[&"teammate_down", 5, 68, 8.0, 1.0],
	[&"revived", 5, 66, 5.0, 1.0],
	[&"streak", 7, 60, 20.0, 1.0],
	[&"dry", 5, 55, 8.0, 0.8],
	[&"power_low", 4, 52, 30.0, 1.0],
	[&"round_start", 5, 50, 10.0, 1.0],
	[&"grenade", 5, 48, 6.0, 0.7],
	[&"reload", 9, 45, 6.0, 0.7],
	[&"low_ammo", 5, 44, 25.0, 1.0],
	[&"round_clear", 5, 42, 10.0, 1.0],
	[&"power_on", 5, 40, 20.0, 1.0],
	[&"buy_big", 4, 38, 5.0, 1.0],
	[&"buy_weapon", 5, 36, 5.0, 1.0],
	[&"door", 5, 34, 8.0, 1.0],
	[&"kill", 10, 30, 5.0, 0.45],
	[&"idle", 5, 10, 40.0, 1.0],
]

## The constants of the HUD parts (`HudBanner`, `HudFuel`, `HudFeed`, `HudGains`, `HudCrosshair`,
## `HudDamage`, `HudHealth`, `HudAmmo`, `HudBossBar`, `HudPrompt`, `HudScoreboard`,
## `ChallengePromptQueue`).
const HUD_TUNING := {
	"banner_in": 0.35,
	"banner_hold": 2.4,
	"banner_out": 0.5,
	"banner_pop_from": 0.92,
	"fuel_in": 0.3,
	"fuel_hold": 4.0,
	"fuel_out": 0.5,
	"feed_life": 4.5,
	"feed_fade": 0.6,
	"gains_life": 2.4,
	"gains_fade": 0.5,
	"gains_merge_window": 0.7,
	"hit_marker_life": 0.22,
	"hit_number_life": 0.9,
	"hit_number_rise": 33.0,
	"damage_arc_life": 1.3,
	"damage_low_fraction": 0.33,
	"damage_pulse_rate": 4.0,
	"health_low_fraction": 0.33,
	"ammo_low_fraction": 0.25,
	"boss_bar_low_fraction": 0.25,
	"prompt_denied_seconds": 1.8,
	"ping_good_ms": 80,
	"ping_fair_ms": 160,
	"challenge_in": 0.25,
	"challenge_out": 0.4,
	"challenge_hold": 2.4,
	"challenge_hold_complete": 3.2,
	"challenge_hold_busy": 1.6,
	"challenge_gap": 0.3,
	"challenge_stale": 20.0,
}

## The constants of `TouchLook` and `TouchControls`.
const TOUCH_TUNING := {
	"radians_per_height": 1.6,
	"slow_speed": 450.0,
	"fast_speed": 2400.0,
	"max_gain": 1.6,
	"velocity_warmup_drags": 3,
	"stick_deadzone": 0.1,
	"sprint_on": 0.95,
	"sprint_off": 0.75,
	"min_hold": 0.09,
	"inset_period": 0.5,
	"haptic_ms": 12,
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
