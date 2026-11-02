# Tuning resources in the inspector

What each tuning resource looks like when you double-click its file in the editor: the groups are the sections, the
unit is in the box, and the `##` comment in the script is the tooltip when you hover a name. Which file holds what, and
where it is loaded, is in [Tuning in the editor](tuning.md#the-tuning-resources). Pictures taken in Godot 4.7.2 on
`main` of 2026-11-02; the first screenful of each is shown (the inspector scrolls).

| **RulesTuning** | **PlayerTuning** | **NightTuning** |
| --- | --- | --- |
| ![RulesTuning in the inspector](tuning/rules_tuning.png) | ![PlayerTuning in the inspector](tuning/player_tuning.png) | ![NightTuning in the inspector](tuning/night_tuning.png) |
| `default_tuning.tres`: eleven parts, each a sub-resource you open | `player_tuning_default.tres`: 15 groups (shown: the first four) | `night_tuning_default.tres` |

| **ZombieTuning** | **WeaponDef** | **GrenadeDef** |
| --- | --- | --- |
| ![ZombieTuning in the inspector](tuning/zombie_tuning.png) | ![WeaponDef in the inspector](tuning/weapon_def_rifle.png) | ![GrenadeDef in the inspector](tuning/grenade_def_frag.png) |
| `zombie_tuning_default.tres` | `weapons/defs/rifle.tres` | `grenades/defs/frag.tres` |

| **SoundMix** | **SoundDef** | **NightSoundTuning** |
| --- | --- | --- |
| ![SoundMix in the inspector](tuning/sound_mix.png) | ![SoundDef in the inspector](tuning/sound_def.png) | ![NightSoundTuning in the inspector](tuning/night_sound_tuning.png) |
| `sound_mix_default.tres` | one sound of a bank in `core/audio/banks/` | `night_sound_tuning_default.tres` |

| **SoldierMoment** | **AimAssistTuning** | **ShotFxTuning** |
| --- | --- | --- |
| ![SoldierMoment in the inspector](tuning/soldier_moment.png) | ![AimAssistTuning in the inspector](tuning/aim_assist_tuning.png) | ![ShotFxTuning in the inspector](tuning/shot_fx_tuning.png) |
| one moment of `soldier_moments_default.tres` | `aim_assist_tuning_default.tres` | `shot_fx_tuning_default.tres` |

| **TouchTuning** | **HudTuning** | **LightTuning** |
| --- | --- | --- |
| ![TouchTuning in the inspector](tuning/touch_tuning.png) | ![HudTuning in the inspector](tuning/hud_tuning.png) | ![LightTuning in the inspector](tuning/light_tuning.png) |
| `touch_tuning_default.tres` | `hud_tuning_default.tres` | `light_tuning_default.tres` |
