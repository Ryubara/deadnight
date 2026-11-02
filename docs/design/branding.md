# Branding

The title, the art that carries it, and every size it goes out at: the Discord Activity, the boot splash, the store
pages and social posts. The app icon and the first key art are in `game/assets/branding/README.md` (#434).

## The wordmark

**Marquee** (the maintainer's pick, 2026-11-01, from three treatments: Marquee, Neon, Board).

| What | Choice |
| --- | --- |
| Face | Bungee Inline, the game's display face (SIL OFL 1.1, committed in `game/assets/fonts/` with its licence). The OFL covers the font file; images made with it carry no licence terms |
| Letters | Cream sign paint (`ink` `#f4ead2`, shading to `#d8cba9` at the foot), the face's inline hairline widened into a red pinstripe (`#d6392f`, the program's one accent) |
| Block shadow | A deep red extrusion down and right (`#7a1d18` to `#3e0f0d`), 15 % of the cap height: the painted sign's "block shadow", the poster's hard offset shadow (style bible, UI look) |
| Keyline | Ink `#1c1612`, 5.5 % of the cap height round the whole letter, so it holds on a bright screen or a dark sky; a faint amber glow behind |
| Tracking | Tight (-0.5 % of the size): the style bible's tight tracking on bold capitals |
| Lockups | `wide` (one line, about 5.8 : 1) and `stacked` (DEAD over NIGHT, both lines the same width, about 1.8 : 1) for tall formats |
| Smallest use | The Steam small capsule (462 x 174): the stacked lockup at 84 % of the height, cap height about 60 px (the wide lockup at full width gives only 46 px and covers the art) |

Built by `tools/blender/title_art/wordmark.py` (plain Python: Pillow, NumPy, SciPy) at a 720 px cap height, saved as
transparent PNG masters. No colour outside the game's tokens.

## Sizes and safe areas

The Discord sizes are the maintainer's (from the Developer Portal); the rest are from the vendors' pages, linked
below. "Title" says where the wordmark sits; "no text" targets carry the art alone.

| Target | Size (px) | Source master | Title | Safe area and rules |
| --- | --- | --- | --- | --- |
| Discord Activity cover art | 1024 x 576 (and a 1920 x 1080 copy) | 16:9 | wide, top, 56 % wide | Shown at 16:9 and cropped to 13:11 on the shelf: the title stays inside the centre 13:11 (the middle 66 % of the width). Discord suggests the title and some art |
| Discord Activity background | 1024 x 576 (and 1920 x 1080) | 16:9 | none | Shown behind the Grid view: art round the edges, the centre left quiet |
| Discord Activity video preview | 640 x 360, H.264 MP4, at most 0.5 MB, at most 10 s (and a 1920 x 1080 copy under the same cap) | animated 16:9 | fades in over the last part | A 5 s camera push with the dead walking, the title at the end |
| Boot splash (desktop) | 1920 x 1080 PNG | 16:9 | wide, top, 58 % wide | `boot_splash/stretch_mode=4` (Cover) fills the window and crops: the title stays inside the centre 4:3 |
| Web loading image | the same file (`index.png`) | 16:9 | as above | The web shell letterboxes it (`object-fit: contain`) on `boot_splash/bg_color`, so the whole image shows |
| Steam header capsule | 920 x 430 | 16:9 crop | wide, top | Logo; no text beyond the title |
| Steam small capsule | 462 x 174 | tight crop on the subject | stacked, left, 84 % high | "A readable logo that nearly fills the capsule" (Steam also makes 184 x 69 and 120 x 45 from it); the whole scene is too small here, so the crop holds only the subject |
| Steam main capsule | 1232 x 706 | 16:9 crop | wide, top | Logo; no text beyond the title |
| Steam vertical capsule | 748 x 896 | 2:3 crop | stacked, top | Logo; no text beyond the title |
| Steam page background | 1438 x 810 | 16:9 crop, darkened | none | Ambient, not too bright |
| Steam library capsule | 600 x 900 | 2:3 | stacked, top | Key art and logo; no text beyond the title |
| Steam library header | 920 x 430 | 16:9 crop | wide, top | Branding; no text beyond the title |
| Steam library hero | 3840 x 1240 PNG | 16:9 crop | **none** (Steam forbids text) | The centre 860 x 380 is never cropped when the window resizes; the logo sits over the hero |
| Steam library logo | 1280 wide, transparent PNG | wordmark | the wide lockup alone | Placed over the hero (bottom left, top or bottom centre, chosen in Steam's tool) |
| Steam event cover / header | 800 x 450 / 1920 x 622 | 16:9 crop | wide, top | Optional branding (Steam shows the name beside it) |
| itch.io cover | 630 x 500 (minimum 315 x 250) | 16:9 crop | wide, top, 86 % wide | The browse thumbnail; a wrong ratio is cropped |
| itch.io banner | 960 x 300 | 16:9 crop, darkened | wide, centred | Replaces the page title; 960 is the default page width |
| Open Graph / X card | 1200 x 630 | 16:9 crop | wide, top | 1.91:1; X crops to 2:1, about 15 px top and bottom, so nothing sits on those edges |
| Social post | 1600 x 900 | 16:9 | wide, top | X shows a single 16:9 image uncropped; keep about 5 % margin |

Sources: [Discord, Activity assets and metadata](https://docs.discord.com/developers/activities/development-guides/assets-and-metadata.md);
[Godot `ProjectSettings` boot splash](https://github.com/godotengine/godot/blob/master/doc/classes/ProjectSettings.xml)
and the [web shell](https://github.com/godotengine/godot/blob/master/misc/dist/html/full-size.html);
[Steam standard store assets](https://partner.steamgames.com/doc/store/assets/standard),
[library assets](https://partner.steamgames.com/doc/store/assets/libraryassets),
[event assets](https://partner.steamgames.com/doc/store/assets/eventassets);
[itch.io page design](https://itch.io/docs/creators/design) (the 630 x 500 cover and 960 px banner are the upload
screen's and an admin's forum numbers, not the docs');
[Meta, sharing images](https://developers.facebook.com/docs/sharing/webmasters/images/) (X's 2:1 crop is from
third-party guides; X's own page did not load).

## The art

Five compositions, each rendered in Blender (Cycles, pinned 5.2.3, headless) from the game's own models only, at
3840 x 2160 (16:9) and 2400 x 3600 (2:3, for the vertical and library capsules), with a clean dark sky above the
action for the title. Every target is a crop of those two masters with the wordmark laid in its safe area, so the
library hero gets the same art with no text.

| | Composition | Built from |
| --- | --- | --- |
| A | Feature presentation: the Soldier on a car roof and the Greaser hold an aisle as the dead pour from under the screen | Soldier and Greaser looks, double shotgun, lever rifle, six zombie looks, cars, speaker posts, street lights, screen frame |
| B | Into the headlights: from behind the dead, a red car's headlamps cut them into silhouettes; the Soldier fires from the roof | the same, a red car with headlamps added in the scene |
| C | The way in: under the lit marquee, the dead shamble in past the ticket booth | the drive-in marquee and ticket booth (their Amber swatch lit), the rest as above |
| D | The headliner: the boss roars over the two players, the projector's beam behind him | the headliner (Boss_Roar), the rest as above |
| E | Back to back: the two players over a burning flare, the dead closing from both sides | as A |

**Picked: B, Into the headlights** (the maintainer, 2026-11-01, #492). **Runner-up: A, Feature presentation**; its
renders and cuts are kept outside the repository and rebuild with the scripts below (`--shots feature`).

B in use:

- The boot splash and the web loading image (`game/assets/branding/keyart_1920x1080.png`) are B's 1920 x 1080 with
  the title; it replaces the first key art ("Back to back", #434).
- Every target above is in `game/assets/branding/source/store/` (Discord, Steam, itch.io, social), with the masters
  (`keyart_clean_3840x2160.png`, `keyart_portrait_2400x3600.png`, no text), the 4K key art with the title and the two
  wordmark lockups beside them in `source/`.
- The small capsule is B's own crop: the car's headlamps and the Soldier on its roof at the right, the stacked title
  at the left (`OVERRIDES` in `post.py`). At 462 x 174 the full scene under a full-width title hid the Soldier and
  left the dead as dark blobs.

Built in the scene from the game's numbers: the projection booth and beam, the screen's glowing face, the flare, the
fog, the headlamps. No third-party asset.

## Licence

Everything here is GDStudio's own work: rendered from the game's own models, and the wordmark drawn from Bungee
Inline. Bungee Inline (and Barlow Condensed, used on the pick sheets only) are already committed with their licence
entries in `game/assets/fonts/LICENSE.md` (SIL OFL 1.1, #373); this work commits no font and no other third-party
file. The OFL covers the font software, not images made with it, so the wordmark images carry no licence terms.

## Rebuilding

```text
uv run --with pillow --with numpy --with scipy python tools/blender/title_art/wordmark.py --out <dir>
export BLENDER="$(gds tool path blender)"
bash tools/blender/title_art/render_all.sh <renders> 3840 2400 128            # masters, GPU
VIDEO=120 VIDEO_W=640 bash tools/blender/title_art/render_all.sh <renders> 0 0 32 headlights  # video frames (and 1920)
uv run --with pillow --with numpy python tools/blender/title_art/post.py --renders <renders> --wordmark <dir> \
    --out <exports> --ffmpeg "$(gds tool path ffmpeg)"
```
