# tools/audio

Everything in `game/assets/audio/` is rendered by `generate.py` from the recipes in this folder (synthesised, seeded
from each sound's name), except 29 files generated with ElevenLabs Sound Effects, fetched by `elevenlabs.py` into
`game/assets/audio/eleven/` and by `elevenlabs_zombies.py` into `game/assets/audio/zombie/`, and the soldier's 115
voice lines, made with ElevenLabs text to speech by `elevenlabs_voice.py` (lines, voice, model and settings are data in
`soldier_voice.json`) into `game/assets/audio/voice/soldier/`. Those three folders carry a `LICENSE.md` (attribution
required, not licensed for commercial use, tracked in issue #252); every other folder holds synthesised files only and
has no licence file because nothing in it is third-party. How: `docs/research/audio.md`.

`beep_report.py` measures the grenade's fuse beep from a 60 fps recording of `game/tests/captures/grenade_pack.tscn` (the
beeps' times, whether their gaps shrink to the blast, their level in the mix against the blast's).

The voice's other tools: `voice_report.py` (the voice's loudness against the guns and the beds, from the stems a night
capture records) and `voice_sheet.py` (the script as a contact sheet).
