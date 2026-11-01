# tools/audio

Everything in `game/assets/audio/` is rendered by `generate.py` from the recipes in this folder (synthesised, seeded
from each sound's name), except 41 files generated with ElevenLabs Sound Effects, fetched by `elevenlabs.py` into
`game/assets/audio/eleven/` and by `elevenlabs_zombies.py` into `game/assets/audio/zombie/`. Those two folders carry a
`LICENSE.md` (attribution required, not licensed for commercial use, tracked in issue #252); every other folder holds
synthesised files only and has no licence file because nothing in it is third-party. How: `docs/research/audio.md`.
