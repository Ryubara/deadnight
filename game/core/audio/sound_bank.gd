class_name SoundBank
extends Resource
## A family of sounds in one file (the zombies' voices, the guns, the beds): a list of `SoundDef`s
## you edit in the inspector. `SoundCatalog.BANKS` lists the files the game loads.

## What the family is, for the person reading the inspector.
@export var label := ""
## The sounds of the family, each a `SoundDef` with its own level, pitch, reach and budget.
@export var sounds: Array[SoundDef] = []
## The family's sounds are not decoded to samples behind the night's loading bar: their files are
## loaded there (cheap), and the samples are made in the background once the night runs, or at
## the sound's first play (`AudioService.preload_sound_for_night`). A family a night does not play
## from its first second (a weapon's shots, a voice) takes this; the decode of all the sounds
## behind the bar was the largest part of the web build's loading, and it grew with every weapon
## (`docs/research/web-export.md`, "Loading a night").
@export var deferred := false
## The family is loaded by nothing but the thing that plays it, when it plays
## (`Audio.preload_sound`):
## the night's loading bar and the background decode leave it alone, so a player who never meets the
## thing (the helicopter drop of the arrival, #1057) pays nothing for its files.
@export var on_demand := false
