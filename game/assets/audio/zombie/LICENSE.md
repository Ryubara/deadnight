# Zombie voice takes generated with ElevenLabs Sound Effects

- Source: ElevenLabs Sound Effects API (`POST /v1/sound-generation`, free tier), generated 2026-11-01 by
  `tools/audio/elevenlabs_zombies.py`: the first run (model v2) made three takes of each sound; a second run (model
  `eleven_text_to_sound_v3`, `prompt_influence` 0.45) made three more of each, and the script kept the best by
  analysis (least hiss above 5 kHz, little silence inside, a quick onset for the short sounds, no clipping), so the
  files below are a mix of the two. Each file's model, prompt and requested length are in `eleven.json`.
- Licence: **Generated with ElevenLabs Sound Effects (free tier); attribution required; not licensed for
  commercial use; replace or relicense before any commercial release.** Tracking issue for the relicensing: #252.
- Decision: the maintainer chose "use it now, credit it" on 2026-11-01 (relayed by the coordinator); the credit is
  on the Credits screen.
- The synthesised variants beside these files (`*_1` and up, from `tools/audio/recipes.py` and
  `zombie_recipes.py`) are original work.

## Takes and their prompts

- `alert_4.ogg` (v2, 1.0 s, influence 0.6):
  "A zombie noticing prey: a short rising rasping snarl, hungry and angry, no music"
- `alert_5.ogg` (v2, 1.0 s, influence 0.6):
  "A zombie noticing prey: a short rising rasping snarl, hungry and angry, no music"
- `alert_6.ogg` (v2, 1.0 s, influence 0.6):
  "A zombie noticing prey: a short rising rasping snarl, hungry and angry, no music"
- `attack_4.ogg` (v3, 1.0 s, influence 0.45):
  "One-shot, a zombie lunging to bite: a short guttural growl and snarl, aggressive, close-mic, dry, no reverb"
- `attack_5.ogg` (v3, 1.0 s, influence 0.45):
  "One-shot, a zombie lunging to bite: a short guttural growl and snarl, aggressive, close-mic, dry, no reverb"
- `attack_6.ogg` (v3, 1.0 s, influence 0.45):
  "One-shot, a zombie lunging to bite: a short guttural growl and snarl, aggressive, close-mic, dry, no reverb"
- `death_3.ogg` (v2, 1.5 s, influence 0.6):
  "A zombie dying: a rattling last groan that falls away into a wet breath, no music"
- `death_4.ogg` (v3, 1.5 s, influence 0.45):
  "One-shot, a zombie dying, a rattling last groan falling away into a wet breath, close-mic, dry, no reverb"
- `death_5.ogg` (v2, 1.5 s, influence 0.6):
  "A zombie dying: a rattling last groan that falls away into a wet breath, no music"
- `groan_5.ogg` (v3, 2.0 s, influence 0.45):
  "One-shot, a dead man's low guttural groan, wet throat rattle, slow and breathy, close-mic, dry, no reverb, no music"
- `groan_6.ogg` (v2, 2.0 s, influence 0.6):
  "A single slow low zombie groan from a dead man's rasping throat, wet and breathy, no music"
- `groan_7.ogg` (v3, 2.0 s, influence 0.45):
  "One-shot, a dead man's low guttural groan, wet throat rattle, slow and breathy, close-mic, dry, no reverb, no music"
- `groan_brute_4.ogg` (v2, 2.0 s, influence 0.6):
  "A huge hulking zombie groaning very low and deep, heavy chest, rumbling, no music"
- `groan_brute_5.ogg` (v3, 2.0 s, influence 0.45):
  "One-shot, a huge hulking zombie's deep rumbling groan from a heavy chest, very low, close-mic, dry, no reverb"
- `groan_crawler_4.ogg` (v3, 1.5 s, influence 0.45):
  "One-shot, a weak pained zombie moan, thin reedy voice, short of breath, close-mic, dry, no reverb, no music"
- `groan_crawler_5.ogg` (v3, 1.5 s, influence 0.45):
  "One-shot, a weak pained zombie moan, thin reedy voice, short of breath, close-mic, dry, no reverb, no music"
- `hurt_4.ogg` (v3, 0.8 s, influence 0.45):
  "One-shot, a zombie shot by a bullet, a short pained raspy grunt and gasp, close-mic, dry, no reverb"
- `hurt_5.ogg` (v2, 0.8 s, influence 0.6):
  "A zombie hit by a bullet: a short pained grunt and gasp, raspy, no music"
- `hurt_6.ogg` (v2, 0.8 s, influence 0.6):
  "A zombie hit by a bullet: a short pained grunt and gasp, raspy, no music"
- `roar_3.ogg` (v2, 3.0 s, influence 0.6):
  "A gigantic monstrous zombie boss roaring, deep distorted growl rising to a roar, cinematic, no music"
- `roar_4.ogg` (v2, 3.0 s, influence 0.6):
  "A gigantic monstrous zombie boss roaring, deep distorted growl rising to a roar, cinematic, no music"
- `shriek_3.ogg` (v3, 1.2 s, influence 0.45):
  "One-shot, a fast undead runner screaming a shrill raspy shriek as it charges, high, close-mic, dry, no reverb"
- `shriek_4.ogg` (v2, 1.2 s, influence 0.6):
  "A fast zombie screaming a shrill raspy shriek as it charges, high and terrifying, no music"
- `shriek_5.ogg` (v3, 1.2 s, influence 0.45):
  "One-shot, a fast undead runner screaming a shrill raspy shriek as it charges, high, close-mic, dry, no reverb"
