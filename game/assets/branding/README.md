# Branding

The app icon ("Marquee ring", picked from six variations in #434) and the title art ("Into the headlights", with the
Marquee wordmark, picked from five compositions in #492; it replaces #434's "Back to back" key art). The sizes, safe
areas and the pick are in `docs/design/branding.md`.

All of it was rendered in Blender (Cycles) from the game's own models only: the Soldier and Greaser from
`assets/characters/soldier_parts/`, the zombies from `assets/characters/zombies/`, the double shotgun and lever rifle
from `assets/weapons/`, and the cars, street lights, screen frame and speaker posts from `assets/props/` and
`assets/drivein/`. The fence, screen face, projection booth, flare, bulb ring and headlamps were modelled in the
render scene. The wordmark is drawn from Bungee Inline, already committed with its licence entry
(`assets/fonts/LICENSE.md`). No other third-party asset is used.

| File | Use |
| --- | --- |
| `icon.png` (256) | `application/config/icon`: the window icon, and the web export's favicon and apple-touch icon |
| `icon.ico` (256, 128, 64, 48, 32, 16) | `application/config/windows_native_icon` |
| `keyart_1920x1080.png` | `application/boot_splash/image`, also the web shell's loading image: the title art with the title inside the centre 4:3 |
| `source/icon_*.png` | the 1024 master and 512, 192, 180, 128, 64, 48, 32, 16 for store pages and other platforms |
| `source/keyart_3840x2160.png` | the 4K key art with the title, for store pages and press |
| `source/keyart_clean_3840x2160.png`, `source/keyart_portrait_2400x3600.png` | the 16:9 and 2:3 masters, no text |
| `source/wordmark_marquee_wide.png`, `source/wordmark_marquee_stacked.png` | the wordmark lockups, transparent |
| `source/store/` | every Discord, Steam, itch.io and social size, and the Discord video preview (`discord/video_*.mp4`) |

`source/` has a `.gdignore`, so Godot neither imports those files nor puts them in an export.
