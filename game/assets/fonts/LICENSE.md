# Typefaces

The two faces of the UI and the HUD, set in `ui/skin/deadnight_tokens.tres` (`font_display`, `font_text`). Both are
open fonts under the SIL Open Font License 1.1, committed unmodified with their licence text. The maintainer
authorised committing them (issue #11, decision of 2026-11-01); the choice and the captures that support it are in
`docs/design/typography.md`.

| Font | Use | Designer | Licence | Source | File | Bytes |
| --- | --- | --- | --- | --- | --- | ---: |
| Bungee Inline | `font_display`: the neon sign, display and title type, the HUD's big numerals | David Jonathan Ross | SIL OFL 1.1, `bungee_inline/OFL.txt` | <https://fonts.google.com/specimen/Bungee+Inline>, <https://github.com/djrrb/Bungee> | `bungee_inline/BungeeInline-Regular.ttf` | 152,376 |
| Barlow Condensed SemiBold | `font_text`: headings, buttons, captions, settings, the HUD's text | Jeremy Tribby | SIL OFL 1.1, `barlow_condensed/OFL.txt` | <https://fonts.google.com/specimen/Barlow+Condensed>, <https://github.com/jpt/barlow> | `barlow_condensed/BarlowCondensed-SemiBold.ttf` | 109,428 |

- Author and copyright lines: "Copyright 2023 The Bungee Project Authors (<https://github.com/djrrb/Bungee>)" and
  "Copyright 2017 The Barlow Project Authors (<https://github.com/jpt/barlow>)".
- Changes: none. The files are the Google Fonts repository's static instances, byte for byte; neither licence names a
  reserved font name.
- Credit: the Credits screen lists both (`ui/credits.tres`, section "Typefaces"), and the Godot Engine's built-in
  Open Sans (SIL OFL 1.1, The Open Sans Project Authors), which `UITokens` keeps as the fallback for a glyph a chosen
  face lacks.
- The OFL allows use, embedding and redistribution in a game; the fonts may not be sold on their own.
