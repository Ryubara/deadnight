class_name RecutStyle
extends Resource
## How a re-cut weapon looks (Deadnight #787): the colours and the pace of the skin
## (`recut_skin.gdshader`), the time the skin takes to sweep over a weapon that has just been
## re-cut, and the bench's light and sparks in the same cold colour. The shipped values are in
## `recut_style_default.tres` (edit that file in the inspector); `RecutStyle.shipped()` is how the
## views and the tests read it. Why it looks like this: `docs/research/recut-skin.md`.

const SHIPPED_PATH := "res://gameplay/weapons/fx/recut_style_default.tres"

static var _shipped: RecutStyle

@export_group("Colours")
## The shadows of the skin: what the weapon's own colours are pulled toward.
@export var deep: Color = Color(0.03, 0.07, 0.16)
## The light of its cells and traces, and of the bench's flash and sparks.
@export var cold: Color = Color(0.1, 0.62, 1.0)
## The white-cyan of the pulse down the barrel and the sweep's front.
@export var spark: Color = Color(0.8, 1.0, 1.0)
## The violet at the very edge of the rim light: the shift of an oil slick.
@export var fringe: Color = Color(0.55, 0.3, 1.0)

@export_group("Look")
## How far the weapon's own colours are pulled toward `deep` (0 keeps them).
@export_range(0.0, 1.0, 0.01) var darken: float = 0.45
@export_range(0.0, 1.0, 0.01) var metallic: float = 0.85
@export_range(0.0, 1.0, 0.01) var roughness: float = 0.32
## The strength of the glow: the emission's multiplier.
@export_range(0.0, 4.0, 0.05) var glow: float = 1.5
## The tightness of the rim light (higher is thinner).
@export_range(0.5, 8.0, 0.1) var rim_power: float = 2.6

@export_group("Cells and pulse")
## A cell of the lattice, in metres at the weapon's real length.
@export_range(0.005, 0.2, 0.001, "suffix:m") var cell_size: float = 0.03
## The share of the cells that burn.
@export_range(0.0, 1.0, 0.01) var live_share: float = 0.2
## How fast the burning cells blink.
@export_range(0.0, 8.0, 0.1) var blink_rate: float = 1.6
## The pulse that runs down the barrel: bands a metre and metres a second's worth of speed.
@export_range(0.1, 8.0, 0.1) var wave_frequency: float = 1.7
@export_range(0.0, 4.0, 0.05) var wave_speed: float = 0.55
## The slow breath over all of it, radians a second.
@export_range(0.0, 8.0, 0.1) var breath_rate: float = 1.8

@export_group("Ignition")
## Seconds the skin takes to sweep over a weapon that has just been re-cut, in the hand.
@export_range(0.05, 5.0, 0.05, "suffix:s") var ignite_seconds: float = 0.7
## The width of the sweep's front, as a share of the weapon's length.
@export_range(0.02, 1.0, 0.01) var front_width: float = 0.22


## The shipped style, loaded once.
static func shipped() -> RecutStyle:
	if _shipped == null:
		_shipped = load(SHIPPED_PATH) as RecutStyle
	return _shipped
