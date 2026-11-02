class_name SoundBank
extends Resource
## A family of sounds in one file (the zombies' voices, the guns, the beds): a list of `SoundDef`s
## you edit in the inspector. `SoundCatalog.BANKS` lists the files the game loads.

## What the family is, for the person reading the inspector.
@export var label := ""
## The sounds of the family, each a `SoundDef` with its own level, pitch, reach and budget.
@export var sounds: Array[SoundDef] = []
