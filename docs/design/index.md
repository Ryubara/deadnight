# Design

The game as it stands. Each subject gets one page here, updated in place as the design changes.

## Pillars

1. **Light is survival.** The generator powers the lot's lights and the projector; the dead are faster off lit ground. Points
   buy fuel, doors and weapons, so every round asks what stays powered.
2. **A night that closes in.** Rounds grow harder and the night darker; the map opens outward from the screen to the
   ticket plaza at the back of the lot.
3. **Played together.** Built for two to eight players (people and bots together) in a browser or a Discord call;
   solo is supported, never the focus.

## The loop

Survive a round, earn points from hits and kills, spend them on doors, weapons, fuel and upgrades, survive the next.
A downed player can be revived until the round ends.

## The lot (planned areas)

| Area | Opens | Notes |
| --- | --- | --- |
| The screen and parked cars | start | the first lit ground |
| Concession stand | early | the prize crane (random weapons), soda-fountain tonics (perks) |
| Generator yard | early | the generator and the fuel; the safest ground, and the most to lose |
| Projection booth | mid | the projector's beam; the re-cut (weapon upgrades) |
| Back lot | mid to late | dim, its lights failing, wrecks and long lanes |
| The ticket plaza (the road door) | late | the lot's last door: a closed court with its own perk machine |

The order, prices and layout are in [the lot](map.md); which map a night is played on, and the picker, in [maps](maps.md).

## Between nights

What carries over from one night to the next, and what never does, is in the [permanent progression
design](progression.md): a night always starts equal, and growth is choice, mastery and identity, never strength.

## Looks

Every player dresses their own character: the [customization screen and how each look reaches the others](customization.md).

## Starting art

The Quaternius Toon Shooter Game Kit (CC0) is the starting style; it may change. Its characters share one rig with
the Quaternius zombie, so animations are shared by bone name. The measured rules (proportions, bevels, triangle
budgets, palette) are in the [style bible](style.md).

## Weapons in hand

How big a weapon is, where the stock, the grip and the support hand sit, and where the barrel points: [Weapons in the
hands](weapon-hold.md).

## Shots on screen

What a shot looks like and how the view answers it: [Shot feedback](shot-feedback.md) (the toon muzzle flash and the
small pooled impacts) and [Camera shake](camera-shake.md) (the light, per-weapon kick of the view, and its setting).

## Tuning the game

Which scene is which: [Scenes](scenes.md). How to play from the editor and where every number lives: [Tuning in the editor](tuning.md).

## Playing together

Who is in the room before a night starts, who hosts, and how a latecomer joins a night in progress: [the lobby](lobby.md).
What happens when it ends, from the camera's pull-back to everyone back in the lobby: [the end of a night](end-of-night.md).
A proposal, not built: a night that can be won, with a kill quota and a chain of steps on each map: [extraction](extraction.md).
