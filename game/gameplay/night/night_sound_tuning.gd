class_name NightSoundTuning
extends Resource
## How the night's sounds behave, as opposed to how loud each sound is (a sound's own level, pitch
## and reach are its `SoundDef` in a bank under `core/audio/banks/`; the voice budget and the
## soldier's voice level are `SoundMix`). Here: how the footsteps follow the pace, the guns' tail
## and impacts, the grenade's beep and bounce, the generator's hum and the shop, the dead's voices
## (how far they carry and how often they speak) and when the soldier speaks. The shipped values
## are in `night_sound_tuning_default.tres`: edit that file in the inspector;
## `NightSoundTuning.current()` is how the game and the tests read it.

const SHIPPED_PATH := "res://gameplay/night/night_sound_tuning_default.tres"

static var _shipped: NightSoundTuning = null

@export_group("Footsteps")
## The pace the step levels are measured from: a step at this ground speed has no level change. It
## is `PlayerTuning.run_speed`.
@export_range(1.0, 12.0, 0.1, "suffix:m/s") var step_pace := 4.8
## The pace of a sprint, which a sprinting step is at least as loud as.
@export_range(1.0, 12.0, 0.1, "suffix:m/s") var step_sprint_pace := 7.0
## Level per decade of speed: 25 makes a sprint (7 m/s) 4 dB up and a crouched run (2.4 m/s) 7.5
## down, the span a real foot spans between creeping and running.
@export_range(0.0, 60.0, 0.5, "suffix:dB") var step_db_per_decade := 25.0
## The quietest a step may be, from the pace ...
@export_range(-60.0, 0.0, 0.5, "suffix:dB") var step_min_db := -18.0
## ... and the loudest.
@export_range(0.0, 24.0, 0.5, "suffix:dB") var step_max_db := 5.0
## Extra level while crouched (the pace already took 7.5).
@export_range(-24.0, 0.0, 0.5, "suffix:dB") var step_crouch_db := -4.0
## Each step's level wanders by up to this much, so a row of steps is not a row of equal ones.
@export_range(0.0, 6.0, 0.1, "suffix:dB") var step_jitter_db := 1.5
## Metres of ground per step for a player seen only in frames (an online teammate).
@export_range(0.5, 4.0, 0.05, "suffix:m") var remote_step_distance := 1.9

@export_group("Guns")
## The tail of a shot starts this long after the report (the lot answers late) ...
@export_range(0.0, 0.5, 0.005, "suffix:s") var tail_delay := 0.03
## ... and up to this much later.
@export_range(0.0, 0.5, 0.005, "suffix:s") var tail_spread := 0.02
## A shot's level wanders by up to this much (the variants and their noise do the rest).
@export_range(0.0, 3.0, 0.1, "suffix:dB") var shot_jitter_db := 0.5
## The most impact sounds one shot makes in the world (a shotgun's pellets are not a hailstorm).
@export_range(0, 12, 1) var max_world_impacts := 3
## How close a pellet's end must be to a zombie for the pellet to count as having hit it.
@export_range(0.1, 5.0, 0.1, "suffix:m") var hit_match_radius := 1.5
## A pellet that ends within this of the weapon's range hit nothing at all (the sky).
@export_range(0.0, 3.0, 0.05, "suffix:m") var range_margin := 0.5
## A reload's steps are this much louder than their own level: another player's, so the team hears
## who is exposed through gunfire (+5: every step of five weapons heard over a tommy gun 6 m off),
## and the player's own, which play flat and already stand out (+2 made them as loud as the
## player's own shots). Measured with `tools/audio/reload_audibility.py` (#683); +6 took a step to
## full scale for 4 samples when it landed on a tommy gun shot (#718).
@export_range(0.0, 18.0, 0.5, "suffix:dB") var teammate_reload_db := 5.0
@export_range(0.0, 12.0, 0.5, "suffix:dB") var own_reload_db := 0.0

@export_group("Grenades")
## The fuse's beep, a time bomb's: the gap between two beeps at the start of the fuse ...
@export_range(0.05, 2.0, 0.01, "suffix:s") var beep_gap_start := 0.5
## ... and at its end, just before the blast.
@export_range(0.05, 2.0, 0.01, "suffix:s") var beep_gap_end := 0.09
## How the gap shrinks between the two: 1 is evenly with the fuse left, more keeps it slow longer
## and then quickens hard at the end, like a time bomb.
@export_range(0.5, 4.0, 0.1) var beep_curve := 1.6
## The beep's level against its own sound, at the start of the fuse ...
@export_range(-12.0, 6.0, 0.5, "suffix:dB") var beep_db_start := -3.0
## ... and at its end: it swells as the blast nears.
@export_range(-12.0, 6.0, 0.5, "suffix:dB") var beep_db_end := 2.0
## A bounce's level goes from the quiet one at rest ...
@export_range(-40.0, 0.0, 0.5, "suffix:dB") var bounce_quiet_db := -9.0
## ... to the loud one at `bounce_fast_speed`.
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var bounce_loud_db := 0.0
@export_range(1.0, 40.0, 0.5, "suffix:m/s") var bounce_fast_speed := 12.0

@export_group("Generator and shop")
## The hum's level, from the generator idling to full load (the synthesised layer) ...
@export_range(-60.0, 6.0, 0.5, "suffix:dB") var hum_idle_db := -15.0
@export_range(-60.0, 6.0, 0.5, "suffix:dB") var hum_full_db := -7.0
## ... and the generated engine under it.
@export_range(-60.0, 6.0, 0.5, "suffix:dB") var engine_idle_db := -22.0
@export_range(-60.0, 6.0, 0.5, "suffix:dB") var engine_full_db := -9.0
## The hum's pitch scale at idle and at full load.
@export_range(0.5, 2.0, 0.01) var hum_idle_pitch := 0.94
@export_range(0.5, 2.0, 0.01) var hum_full_pitch := 1.05
## How far a starving engine's pitch wobbles (a share), and how fast.
@export_range(0.0, 0.3, 0.005) var starve_wobble := 0.035
@export_range(0.5, 20.0, 0.5, "suffix:Hz") var starve_wobble_hz := 6.0
## How fast a level moves toward its target ...
@export_range(1.0, 200.0, 1.0, "suffix:dB/s") var slew_db_per_s := 24.0
## ... and the level that counts as off.
@export_range(-120.0, -20.0, 1.0, "suffix:dB") var off_db := -60.0
## Seconds between the generator's sputters when the tank is barely low ...
@export_range(0.2, 20.0, 0.1, "suffix:s") var sputter_gap_low := 4.0
## ... and when it is nearly dry.
@export_range(0.2, 20.0, 0.1, "suffix:s") var sputter_gap_dry := 1.0
## The tense bed starts this long after a round does, when the sting's front is over.
@export_range(0.0, 10.0, 0.1, "suffix:s") var bed_delay := 2.4
## A purchase with several sounds plays them this far apart.
@export_range(0.0, 1.0, 0.05, "suffix:s") var buy_gap := 0.2
## The prize ding comes this long after the crane's claw starts up with it.
@export_range(0.0, 2.0, 0.05, "suffix:s") var prize_ding_delay := 0.35

@export_group("The dead's voices")
## A chasing zombie that first comes within this snarls once.
@export_range(1.0, 100.0, 1.0, "suffix:m") var alert_range := 22.0
## Idle voices are considered within this ...
@export_range(1.0, 100.0, 1.0, "suffix:m") var idle_range := 36.0
## ... and feet are started within this.
@export_range(1.0, 100.0, 1.0, "suffix:m") var step_range := 28.0
## At most one idle voice starts every so often (a random gap between these two), however many are
## due at once ...
@export_range(0.0, 10.0, 0.05, "suffix:s") var idle_gap_min := 0.6
@export_range(0.0, 10.0, 0.05, "suffix:s") var idle_gap_max := 1.6
## ... and one zombie speaks again after this long (a random time between these two).
@export_range(0.0, 60.0, 0.5, "suffix:s") var idle_self_min := 5.0
@export_range(0.0, 60.0, 0.5, "suffix:s") var idle_self_max := 11.0
## An idle voice is picked at random among this many of the nearest zombies that are due.
@export_range(1, 12, 1) var idle_pool := 3
## No two snarls closer than this, so a pack coming into range is not one wall of sound.
@export_range(0.0, 3.0, 0.05, "suffix:s") var alert_gap := 0.35
## A zombie's hurt voice is not repeated sooner than this.
@export_range(0.0, 3.0, 0.05, "suffix:s") var hurt_gap := 0.4
## Seconds between a repeated swing's grunts while it keeps swinging (at a board).
@export_range(0.1, 5.0, 0.05, "suffix:s") var swing_repeat := 1.2
## The headliner's fall is the roar, this much quieter than its entrance.
@export_range(-24.0, 0.0, 0.5, "suffix:dB") var boss_death_db := -8.0

@export_group("Voice director")
## Silence after a line before the next may start.
@export_range(0.0, 5.0, 0.05, "suffix:s") var line_gap := 0.5
## From this priority up a line may cut a lower one that is speaking.
@export_range(0, 200, 1) var interrupt_priority := 80
## Any line may cut one this many ranks below it.
@export_range(0, 200, 1) var cut_margin := 25
## How many of a moment's last takes it will not play again.
@export_range(0, 8, 1) var remember_takes := 3

@export_group("When the soldier speaks")
## Kills in a row that make a streak ...
@export_range(2, 20, 1) var streak_kills := 4
## ... and the longest gap between two of them.
@export_range(1.0, 30.0, 0.5, "suffix:s") var streak_window := 6.0
## Below this share of health a blow is a close call.
@export_range(0.0, 1.0, 0.01) var low_health := 0.35
## A weapon that costs this much is a big buy.
@export_range(0, 10000, 50, "suffix:pts") var big_buy := 1000
## A low magazine: the rounds left when there is no reserve, as a share of a full magazine.
@export_range(0.0, 1.0, 0.01) var low_magazine := 0.4
## Seconds after a round starts before the soldier speaks (the sting and the score first) ...
@export_range(0.0, 10.0, 0.1, "suffix:s") var round_start_delay := 1.6
## ... and after it ends.
@export_range(0.0, 10.0, 0.1, "suffix:s") var round_clear_delay := 2.4
## The boss is seen this long after it is told of.
@export_range(0.0, 10.0, 0.1, "suffix:s") var boss_delay := 0.8
## A teammate who sees someone go down speaks this long after the fallen one's line.
@export_range(0.0, 5.0, 0.1, "suffix:s") var rescue_delay := 0.4
## The soldier muses aloud after this many quiet seconds, in a break that has `idle_margin` more
## seconds to run (before the night too) ...
@export_range(0.0, 60.0, 0.5, "suffix:s") var idle_after := 5.0
@export_range(0.0, 60.0, 0.5, "suffix:s") var idle_margin := 8.0
## ... or in a round after this many seconds with no dead within `lull_distance` metres.
@export_range(0.0, 60.0, 0.5, "suffix:s") var lull := 10.0
@export_range(1.0, 100.0, 1.0, "suffix:m") var lull_distance := 30.0


## The shipped table, loaded once and shared; do not change it at run time (a test that needs
## another value makes a copy with `duplicate()`).
static func current() -> NightSoundTuning:
	if _shipped == null:
		_shipped = load(SHIPPED_PATH) as NightSoundTuning
	return _shipped
