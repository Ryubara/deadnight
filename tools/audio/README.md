# tools/audio

Everything in `game/assets/audio/` is rendered by `generate.py` from the recipes in this folder (synthesised, seeded
from each sound's name), except 29 files generated with ElevenLabs Sound Effects, fetched by `elevenlabs.py` into
`game/assets/audio/eleven/` and by `elevenlabs_zombies.py` into `game/assets/audio/zombie/`, and the two soldiers'
115 voice lines each, made with ElevenLabs text to speech by `elevenlabs_voice.py` (lines, voice, model and settings are
data in `soldier_voice.json` for the male voice, into `game/assets/audio/voice/soldier/`, and `soldier_voice_female.json`
for the female one, `--voice female`, into `game/assets/audio/voice/soldier_female/`). Those four folders carry a
`LICENSE.md` (attribution required, not licensed for commercial use, tracked in issue #252); every other folder holds
synthesised files only and has no licence file because nothing in it is third-party. How: `docs/research/audio.md`.

`beep_report.py` measures the grenade's fuse beep from a 60 fps recording of `game/tests/captures/grenade_pack.tscn` (the
beeps' times, whether their gaps shrink to the blast, their level in the mix against the blast's).

The voice's other tools: `voice_report.py` (the voice's loudness against the guns and the beds, from the stems a night
capture records) and `voice_sheet.py` (the script as a contact sheet; `--voice female` for hers).

The second map's sounds (the depot's room tone, the yard, a debris blocker, feet on wood) are `map_recipes.py`, synthesised
like the rest; `smallmap_levels.py` measures them (`table`: level and reach from the banks and the files; `capture`: the
mix of the walk through the map, level by stage). `docs/research/maps/small-map-audio.md` has the numbers.

Headroom (#718): `headroom.py` reads recordings of `game/tests/captures/audio_headroom.tscn` (the player's own gun fired
without a break while a reload, a teammate's gun, the dead's voices or the lot's sounds land on it) and prints, for each
pair, the peak of the mix and the samples over -1 dBFS, then the gun alone (RMS, crest factor, loudness) and each sound's
own peak; `gun_levels.py` measures the guns against the beds. `docs/research/gun-audio.md#headroom-under-other-sounds`
has the numbers.

The crickets (#781): `cricket_levels.py` measures them (`check`: the chirp rate range and whole chirps in the loop;
`measure`: chirps a second, loudness and the level in their own band against the highway; `capture`: the same on the
mix of `game/tests/captures/audio_quiet_night.tscn`, the beds alone). `docs/research/audio.md#the-crickets-cut-again-781`.

Close sounds (#753): `close_levels.py` reads a run of the same capture with `--own=none --cells=zombie,world
--all-variants --close` (every variant of the dead's voices and the lot's sounds, one at a time, 1.2 m from the
listener, where the player's `max_db` holds the level) and prints each sound's ceiling, its highest sample and its
loudest 400 ms; `--table game/tests/core/close_sound_levels.json` writes the table `test_close_sound_levels.gd` pins.
`docs/research/gun-audio.md#close-sounds-under-gunfire` has the rule and the numbers.

Sharp sounds (#762): `limiter.py` is a look-ahead peak limiter with a smooth gain curve for recipes (`limit_crest(x,
crest_db)` holds the highest sample `crest_db` over the loudest 400 ms); the boards, the door and the debris blocker end
their recipes with it, their `peak_db` lowered and `near_cap_db` raised by what it took off, so a close sharp sound is
louder at the same peak (the web build ignores a bus limiter). `docs/research/gun-audio.md#the-sharp-sounds-limited-in-their-recipe-762`.

The energy weapons, the re-cut layer and the bench's sequence (#791) are `energy_recipes.py` (the ray gun, the freeze
gun, `recut_layer` and its element layers, `buy_recut`), in `game/assets/audio/energy/` (and `world/buy_recut_1.ogg`);
`energy_levels.py` reads a recording of `game/tools/bench/audio_energy_bench.tscn` (each weapon plain and re-cut, the beds,
then the close sounds one at a time) and prints what `gun_levels.py` prints plus what the layer adds to a shot (peak,
tail, bright band) and the close peaks; `--table game/tests/night/energy_levels.json` writes what
`test_energy_audio_rules.gd` pins. `docs/research/gun-audio.md#the-energy-weapons-and-the-re-cut-layer-791` has the numbers.

The flare gun's report (#761) is limited the same way (`limit_crest`); `gun_levels.py --table` also writes
a SHA-256 of every gun file it played, which `test_gun_audio_rules.gd` checks.

The drive-in's wind (#782): `wind_recipes.py` renders the base loop, the eight gust files (`generate.py` hands a recipe
that takes a `variant` argument its file number, so one table of shapes makes the eight) and the details;
`wind_levels.py` reads them against the other beds (`files`) and a night's gusts in the Ambience bus of
`game/tests/captures/audio_wind_night.tscn` (`night`, with the wind alone, the beds, and the beds without the wind).
`audio_headroom.tscn --wind` runs the wind at its strongest under the headroom cells. `docs/research/wind.md` has the
sources and the numbers.

The second batch of firearms (#790: PPSh, M249, M4A1, .50 calibre, MP5, 870 pump, dual pistols) is `gun_recipes_2.py`,
built from `weapon_recipes.py`'s `report` and `tail` and listed by `generate.py`; its sounds are `shot_`, `tail_`,
`equip_` and `dry_` plus the gun id, and `reload_<gun>_<step>`.
`docs/research/gun-audio.md#the-second-batch-of-firearms-790`.

The perk drink (#912) is `drink_recipes.py` (`drink_open`, `drink_gulp`, `drink_discard`), in `game/assets/audio/perks/`,
played by the drink clip's events from the deferred `perks` bank (`docs/design/animation.md#drink`).
