class_name LightTuning
extends Resource
## The lot's light in one resource: how far a lamp reaches and how it fails with the tank (both the
## rules' business: the dead keep to their round's pace on lit ground), how the night darkens as the
## rounds go, and how bright each fixture burns. The shipped values are in
## `light_tuning_default.tres`: edit that file in the inspector; `LightTuning.current()` is how the
## game and the tests read it. How light the night is per round is `RoundTuning`
## (`ambient_start` and the falloff): this resource says what the scene does with that number.

const SHIPPED_PATH := "res://world/drive_in/light_tuning_default.tres"

static var _shipped: LightTuning = null

@export_group("Lamps (the rules read these)")
## Ground within this of a lit lamp is lit: the dead there keep to their round's pace.
@export_range(1.0, 20.0, 0.5, "suffix:m") var lamp_reach := 6.0
## A failing tank changes a lamp's state every this many ticks (60 a second: 5 is about 12 times a
## second).
@export_range(1, 60, 1, "suffix:ticks") var flicker_ticks := 5
## How much light a lamp keeps when the tank is nearly dry ...
@export_range(0.0, 1.0, 0.01) var sag_floor := 0.35
## ... and the share it keeps in the dropouts of a flicker.
@export_range(0.0, 1.0, 0.01) var dropout := 0.12

@export_group("Failing battery (the back lot's lights, FailingBattery)")
## How much of its light a lamp gives on average: dimmed ...
@export_range(0.1, 1.0, 0.01) var failing_base := 0.6
## ... drifting by this much either side over a few seconds ...
@export_range(0.0, 0.3, 0.01) var failing_wander := 0.08
## ... and the share it keeps at the bottom of a dip (above 0: the lights never go out).
@export_range(0.02, 0.5, 0.01) var failing_floor := 0.12
## One event at most in each cycle of this many seconds (the quiet between two is at least 1.5 s).
@export_range(3.2, 10.0, 0.1, "suffix:s") var failing_cycle := 3.6
## The flicker's seed: the same number gives the same lights, a test or a night.
@export var failing_seed := 851

@export_group("The night closing in")
## A change of round takes this long to settle (a break is 20 s).
@export_range(0.5, 20.0, 0.5, "suffix:s") var ease_seconds := 12.0
## At the darkest round: the share left of the scene's ambient light ...
@export_range(0.0, 1.0, 0.01) var darkest_ambient := 0.35
## ... of the moon's light ...
@export_range(0.0, 1.0, 0.01) var darkest_moon := 0.5
## ... of the sky's and the fog's brightness (the fog is matched to the sky's horizon by hand) ...
@export_range(0.0, 1.0, 0.01) var darkest_sky := 0.5
## ... and the fog's density as a multiple of the scene's: the view closes in too.
@export_range(1.0, 5.0, 0.05, "suffix:x") var darkest_fog_density := 1.7

@export_group("Lamp posts")
## How much of its albedo the bulb keeps when it is dark.
@export_range(0.0, 1.0, 0.01) var bulb_dark_albedo := 0.25
## The lens's emission, the halo's and the ground pool's brightness at full glow.
@export_range(0.0, 10.0, 0.05) var bulb_energy := 3.0
@export_range(0.0, 10.0, 0.05) var bulb_halo_energy := 0.9
@export_range(0.0, 10.0, 0.05) var bulb_pool_energy := 0.5

@export_group("Breaker posts")
## How much of the lamp's colour glows when it is off ...
@export_range(0.0, 10.0, 0.05) var switch_glow_off := 0.5
## ... and on.
@export_range(0.0, 10.0, 0.05) var switch_glow_on := 2.0
## The halo round the lamp, so a post reads from across the lot: bright green on ...
@export_range(0.0, 10.0, 0.05) var switch_halo_on := 1.1
## ... and a dull red off.
@export_range(0.0, 10.0, 0.05) var switch_halo_off := 0.45

@export_group("Neon sign, screen, projector")
## How brightly the neon tubes burn at level 1, and their halo.
@export_range(0.0, 10.0, 0.05) var neon_tube_energy := 3.0
@export_range(0.0, 10.0, 0.05) var neon_halo_energy := 0.9
## How brightly the screen's face and its spill on the lot burn at level 1.
@export_range(0.0, 10.0, 0.05) var screen_face_energy := 1.0
@export_range(0.0, 10.0, 0.05) var screen_spill_energy := 0.1
## A glow pane's brightness at level 1.
@export_range(0.0, 10.0, 0.05) var pane_energy := 0.55
## The projector's beam and its halo at the lens ...
@export_range(0.0, 10.0, 0.01) var beam_energy := 0.14
@export_range(0.0, 10.0, 0.05) var beam_halo_energy := 1.5
## ... and the haze's brightness at the lens and at the screen.
@export_range(0.0, 2.0, 0.01) var beam_near := 1.0
@export_range(0.0, 2.0, 0.01) var beam_far := 0.12


## The shipped table, loaded once and shared; do not change it at run time (a test that needs
## another value makes a copy with `duplicate()`).
static func current() -> LightTuning:
	if _shipped == null:
		_shipped = load(SHIPPED_PATH) as LightTuning
	return _shipped
