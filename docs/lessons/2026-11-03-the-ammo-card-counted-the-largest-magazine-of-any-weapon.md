# The ammo card called a full double-barrel "LOW" because it counted the largest magazine of any weapon

2026-11-03

- **Symptom:** CI failed `test_a_weapon_put_away_mid_reload_does_not_stay_reloading` (hint "LOW", expected empty) on the
  double-barrel pull request (#684); my own capture showed "2/16 LOW" on a full gun and I read it as fine.
- **Cause:** `HudAmmo` kept the largest magazine ever seen as the weapon's full size and called anything at a quarter of
  it low. That held while every gun had a magazine of 6 or more; with a magazine of 2 after a bigger one, 2 of 8 was low.
- **Fix:** the size is counted per weapon (it starts over when the weapon in hand changes), and a test gives the smg and
  then the shotgun and expects no hint. Look at the HUD text in a capture, not only the picture of the gun. A change to
  a weapon's magazine runs `tests/ui` and `tests/night/test_night_hud*.gd`, which read the HUD's own numbers, as well
  as the weapons folder.
- **Documented:** none beyond this lesson.
