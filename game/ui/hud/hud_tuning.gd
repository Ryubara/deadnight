class_name HudTuning
extends Resource
## How long the HUD's things stay and when it warns, in one resource: the round banner, the fuel
## panel, the feeds, the hit markers and numbers, the damage arcs, the challenge prompts, the low
## health, ammunition and boss warnings, and the scoreboard's ping colours. Sizes, positions and
## colours are the skin (`UITokens`) and the layout (`HudStyle`), not here. The shipped values are
## in `hud_tuning_default.tres`: edit that file in the inspector; `HudTuning.current()` is how the
## HUD and the tests read it.

const SHIPPED_PATH := "res://ui/hud/hud_tuning_default.tres"

static var _shipped: HudTuning = null

@export_group("Round banner")
## The banner comes in over this long ...
@export_range(0.05, 2.0, 0.05, "suffix:s") var banner_in := 0.35
## ... holds this long (a caller may ask for another) ...
@export_range(0.2, 10.0, 0.1, "suffix:s") var banner_hold := 2.4
## ... and leaves over this long.
@export_range(0.05, 2.0, 0.05, "suffix:s") var banner_out := 0.5
## The board grows from this scale to full size as it appears (skipped when motion is reduced).
@export_range(0.5, 1.0, 0.01) var banner_pop_from := 0.92

@export_group("Generator panel")
## The fuel panel fades in over this long ...
@export_range(0.05, 2.0, 0.05, "suffix:s") var fuel_in := 0.3
## ... stays this long after the last change ...
@export_range(0.5, 20.0, 0.5, "suffix:s") var fuel_hold := 4.0
## ... and slides out over this long.
@export_range(0.05, 2.0, 0.05, "suffix:s") var fuel_out := 0.5

@export_group("Feeds")
## A line of the event feed (top right) stays this long ...
@export_range(0.5, 30.0, 0.1, "suffix:s") var feed_life := 4.5
## ... and fades over the last of it.
@export_range(0.05, 3.0, 0.05, "suffix:s") var feed_fade := 0.6
## A points gain (above the ammunition) stays this long ...
@export_range(0.5, 10.0, 0.1, "suffix:s") var gains_life := 2.4
## ... fades over the last of it ...
@export_range(0.05, 3.0, 0.05, "suffix:s") var gains_fade := 0.5
## ... and a hit within this long of the last gain of the same kind adds to it.
@export_range(0.0, 3.0, 0.05, "suffix:s") var gains_merge_window := 0.7

@export_group("Hits and damage")
## A hit marker on the crosshair lasts this long ...
@export_range(0.05, 2.0, 0.01, "suffix:s") var hit_marker_life := 0.22
## ... a damage number this long ...
@export_range(0.1, 5.0, 0.05, "suffix:s") var hit_number_life := 0.9
## ... rising this many canvas units over its life.
@export_range(0.0, 200.0, 1.0) var hit_number_rise := 33.0
## An arc pointing at where a blow came from lasts this long.
@export_range(0.1, 5.0, 0.05, "suffix:s") var damage_arc_life := 1.3
## The screen's red frame starts pulsing under this share of health, at this rate ...
@export_range(0.0, 1.0, 0.01) var damage_low_fraction := 0.33
@export_range(0.5, 20.0, 0.5, "suffix:/s") var damage_pulse_rate := 4.0

@export_group("Warnings")
## The health bar turns hot under this share of health.
@export_range(0.0, 1.0, 0.01) var health_low_fraction := 0.33
## The magazine counts as low at or under this share of its size (at least one round).
@export_range(0.0, 1.0, 0.01) var ammo_low_fraction := 0.25
## A boss's bar turns hot under this share of its health.
@export_range(0.0, 1.0, 0.01) var boss_bar_low_fraction := 0.25
## A prompt shows "denied" this long after a refused purchase.
@export_range(0.2, 5.0, 0.1, "suffix:s") var prompt_denied_seconds := 1.8
## A ping up to this many milliseconds reads good ...
@export_range(10, 500, 5, "suffix:ms") var ping_good_ms := 80
## ... up to this fair, and past it poor.
@export_range(10, 1000, 5, "suffix:ms") var ping_fair_ms := 160

@export_group("Challenge prompts")
## A prompt comes in over this long ...
@export_range(0.05, 2.0, 0.05, "suffix:s") var challenge_in := 0.25
## ... leaves over this long ...
@export_range(0.05, 2.0, 0.05, "suffix:s") var challenge_out := 0.4
## ... and holds this long: for a step, for a finished challenge, and when others wait behind it.
@export_range(0.5, 10.0, 0.1, "suffix:s") var challenge_hold := 2.4
@export_range(0.5, 10.0, 0.1, "suffix:s") var challenge_hold_complete := 3.2
@export_range(0.5, 10.0, 0.1, "suffix:s") var challenge_hold_busy := 1.6
## Quiet between one prompt and the next.
@export_range(0.0, 3.0, 0.05, "suffix:s") var challenge_gap := 0.3
## A prompt that waited this long is dropped: it would describe something long gone.
@export_range(1.0, 120.0, 1.0, "suffix:s") var challenge_stale := 20.0

@export_group("Progression popups")
## A card drops in over this long (with a small overshoot), holds, and leaves over `popup_out` ...
@export_range(0.05, 1.0, 0.05, "suffix:s") var popup_in := 0.25
@export_range(0.05, 1.0, 0.05, "suffix:s") var popup_out := 0.2
## ... a level card holds this long, an unlock card, a tier card and a finished challenge ...
@export_range(0.5, 10.0, 0.1, "suffix:s") var popup_hold_level := 2.6
@export_range(0.5, 10.0, 0.1, "suffix:s") var popup_hold_unlock := 2.0
@export_range(0.5, 10.0, 0.1, "suffix:s") var popup_hold_tier := 3.6
@export_range(0.5, 10.0, 0.1, "suffix:s") var popup_hold_challenge := 3.0
## ... and no longer than this when others wait behind it.
@export_range(0.5, 10.0, 0.1, "suffix:s") var popup_hold_busy := 1.6
## The least time between one card starting and the next (a stack of unlocks).
@export_range(0.0, 1.0, 0.05, "suffix:s") var popup_start_gap := 0.15
## A card that is full in stays at least this long before a waiting card sends it away.
@export_range(0.2, 5.0, 0.1, "suffix:s") var popup_min_show := 1.0
## The cards under a card that leaves slide up over this long.
@export_range(0.05, 1.0, 0.05, "suffix:s") var popup_slide := 0.25
## How far above its place a card starts, canvas units.
@export_range(0.0, 80.0, 1.0) var popup_drop := 30.0


## The shipped table, loaded once and shared; do not change it at run time (a test that needs
## another value makes a copy with `duplicate()`).
static func current() -> HudTuning:
	if _shipped == null:
		_shipped = load(SHIPPED_PATH) as HudTuning
	return _shipped
