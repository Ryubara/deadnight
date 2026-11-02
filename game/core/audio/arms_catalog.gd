class_name ArmsCatalog
extends RefCounted
## The rule the weapons' and the lot's machines' sounds follow (the sounds themselves are in the
## banks under `core/audio/banks/`, `weapons.tres` and `world.tres`); the design is
## `docs/design/audio.md`.
##
## A gunshot is two voices, each with its own random variant: the report (`shot_*`: the whole
## shot as the shooter hears it a few feet from the muzzle, a click, a crack, a roar and a thump,
## synthesised) and a tail (`tail_*`, played a few hundredths late and far under it: what the lot
## gives back). The files are `tools/audio/weapon_recipes.py`; why they are what they are, and
## the rules every firearm follows (pitch, level, loudness against the night), is
## `docs/research/gun-audio.md`.

## The one pitch rule of every firearm voice: a random shift within plus or minus this many
## semitones (about 1 percent). Automatic fire varies in its noise, not in its note: at the
## 13 shots a second of the tommy gun a wider shift is heard as a gun that cannot hold a pitch.
const FIREARM_PITCH_SEMITONES := 0.15
