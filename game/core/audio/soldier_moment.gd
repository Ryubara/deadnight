class_name SoldierMoment
extends Resource
## One moment of the night the soldier may speak about (`SoldierMoments`): how it ranks against the
## others, how often it is said and how many takes there are of it.

## The moment's name, the event the night says: it names the files (`<event>_<n>.ogg`).
@export var event: StringName = &""
## How many take files there are (`voice/soldier/<event>_<n>.ogg`). Change it only with the files.
@export_range(1, 20, 1) var takes := 1
## A line may cut the one speaking only from `NightSoundTuning.interrupt_priority` up (or when it
## ranks `cut_margin` above), and then only a lower one. Higher is more urgent.
@export_range(0, 200, 1) var priority := 50
## Seconds before the same player says this moment again.
@export_range(0.0, 120.0, 0.5, "suffix:s") var cooldown := 0.0
## The share of the times this happens that the soldier says anything, so the commonest moments
## are not a running commentary.
@export_range(0.0, 1.0, 0.05) var chance := 1.0
