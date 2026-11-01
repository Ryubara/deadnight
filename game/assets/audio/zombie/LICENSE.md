# Zombie voice takes generated with ElevenLabs Sound Effects

- Source: ElevenLabs Sound Effects API (`POST /v1/sound-generation`, free tier), generated 2026-11-01 by
  `tools/audio/elevenlabs_zombies.py`, which trims, normalises and encodes each take.
- Licence: **Generated with ElevenLabs Sound Effects (free tier); attribution required; not licensed for
  commercial use; replace or relicense before any commercial release.** Tracking issue for the relicensing: #252.
- Decision: the maintainer chose "use it now, credit it" on 2026-11-01 (relayed by the coordinator); the credit is
  on the Credits screen.
- The synthesised variants beside these files (`*_1` and up, from `tools/audio/recipes.py` and
  `zombie_recipes.py`) are original work.

## Takes and their prompts

Each take is one request with `prompt_influence` 0.6 and the length shown.

- `groan_5.ogg`, `groan_6.ogg`, `groan_7.ogg` (2.0 s each):
  "A single slow low zombie groan from a dead man's rasping throat, wet and breathy, no music"
- `groan_brute_4.ogg`, `groan_brute_5.ogg` (2.0 s each):
  "A huge hulking zombie groaning very low and deep, heavy chest, rumbling, no music"
- `groan_crawler_4.ogg`, `groan_crawler_5.ogg` (1.5 s each):
  "A weak pained zombie moan, thin reedy voice, short of breath, no music"
- `alert_4.ogg`, `alert_5.ogg`, `alert_6.ogg` (1.0 s each):
  "A zombie noticing prey: a short rising rasping snarl, hungry and angry, no music"
- `attack_4.ogg`, `attack_5.ogg`, `attack_6.ogg` (1.0 s each):
  "A zombie lunging to attack: a guttural growling snarl and bite, aggressive, no music"
- `hurt_4.ogg`, `hurt_5.ogg`, `hurt_6.ogg` (0.8 s each):
  "A zombie hit by a bullet: a short pained grunt and gasp, raspy, no music"
- `death_3.ogg`, `death_4.ogg`, `death_5.ogg` (1.5 s each):
  "A zombie dying: a rattling last groan that falls away into a wet breath, no music"
- `shriek_3.ogg`, `shriek_4.ogg`, `shriek_5.ogg` (1.2 s each):
  "A fast zombie screaming a shrill raspy shriek as it charges, high and terrifying, no music"
- `roar_3.ogg`, `roar_4.ogg` (3.0 s each):
  "A gigantic monstrous zombie boss roaring, deep distorted growl rising to a roar, cinematic, no music"
