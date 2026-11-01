# Typography

Six display + text pairings for Deadnight's UI, shown on the same mock main menu, with licences, sources and a
recommendation. **Decided (issue #11, maintainer 2026-11-01): Marquee, Bungee Inline + Barlow Condensed SemiBold**,
both OFL and committed under `game/assets/fonts` with their licence entry ([the decision](#decision)). The visual
rules the pairings must serve are in the [UI look](style.md#ui-look) section of the style bible.

## What the era used

| Source | What it tells us |
| --- | --- |
| Nearly every title before the 1960s was hand lettered: studios hired lettering artists because type was too limiting ([Mark Simonson](https://www.marksimonson.com/notebook/view/best-movie-title-site-yet/)) | Film and marquee titles were drawn, so a typeface is always a stand-in: pick faces with a *drawn* feel (uneven weight, tight fit), not geometric neutrality |
| Marquee and privilege signs of the 1950s-60s used condensed sans lettering ([Fontbros](https://www.fontbros.com/font-family/privilege-sign-two)) | Tall condensed capitals for anything read from a car |
| Marquee lettering is bold and traced by lamps or neon; one Kansas marquee cut parallel lines through its letters ([JNL Theater Sign](https://www.myfonts.com/collections/theater-sign-jnl-font-jeff-levine)) | An *inline* display face is the closest open match to a lit marquee letter |
| Horror and sci-fi posters used giant, uneven lettering for effect; *The Blob* (1958) dripped | Heavy, slightly rough poster faces for the title |
| Sign-painter and neon scripts were the other voice, the cursive on the diner and motel sign | One script, used once, for the lit sign |
| Tickets and concession paper were printed in typewriter-like and condensed gothic faces | A mono or condensed face for small print and numbers |

These are modern summaries of a hand-lettered era, not primary sources; the faces below are judged by how they look in
the mock, not by a claim of period accuracy.

## Candidates

Every file was downloaded from the [Google Fonts repository](https://github.com/google/fonts) (licence text and
`METADATA.pb` alongside each file) and rendered by `game/ui/specimens/typography_specimen.tscn`.

| # | Pairing | Display face | Text face | Fit |
| --- | --- | --- | --- | --- |
| 1 | **Marquee** | Bungee Inline | Barlow Condensed SemiBold | Signage first: Bungee comes from stacked urban signs and the inline reads as a lit channel letter; Barlow Condensed draws on highway signs and licence plates. Clear at every size, many static weights |
| 2 | **Neon script** | Yellowtail | Jost Medium | The lit roadside sign: a flat brush script with a sign-painter cadence, glowing. Jost is a clean text face but reads as modern geometric; the HUD digits use Jost because script numerals are weak |
| 3 | **Ticket stub** | Big Shoulders Display Black | Courier Prime Bold | Tight condensed American gothic plus typewriter print: the ticket and poster-credits voice. Plain and honest, the least "lit"; Courier is wide, so menus run long |
| 4 | **B-movie poster** | Bowlby One | Archivo (width 75, SemiBold) | Heavy early-20th-century poster forms with a roughened edge; the loudest title. Archivo's width axis gives a condensed menu face from one file |
| 5 | **Poster gothic** | League Gothic | Special Elite | Alternate Gothic (1903): very tall, tight, period-true for posters. Special Elite is a typewriter with ink grunge: characterful but harder to read at menu and HUD sizes |
| 6 | **Diner** | Fontdiner Swanky | Libre Franklin SemiBold | The cheerful soda-fountain end: swash caps, bounce. Franklin Gothic was the 1950s print workhorse. Too cute for a zombie game unless the tone is camp |

## Licences and sources

All are free for commercial use and may be embedded and redistributed in a game. **SIL OFL 1.1**: keep the licence
text with the font, do not sell the font alone, do not reuse a reserved name for a modified font. **Apache 2.0**: keep
the licence text and a notice. The credits screen lists each font used. Licence questions are the maintainer's.

| Family | Designer | Licence | Source | Size |
| --- | --- | --- | --- | --- |
| Bungee Inline | David Jonathan Ross | OFL 1.1 | [Google Fonts](https://fonts.google.com/specimen/Bungee+Inline), [repository](https://github.com/djrrb/Bungee) | 148 KB |
| Barlow Condensed | Jeremy Tribby | OFL 1.1 | [Google Fonts](https://fonts.google.com/specimen/Barlow+Condensed), [repository](https://github.com/jpt/barlow) | about 105 KB per weight |
| Yellowtail | Astigmatic | Apache 2.0 | [Google Fonts](https://fonts.google.com/specimen/Yellowtail) | 60 KB |
| Jost | Owen Earl | OFL 1.1 | [Google Fonts](https://fonts.google.com/specimen/Jost), [repository](https://github.com/indestructible-type/Jost) | 131 KB (variable) |
| Big Shoulders Display | Patric King | OFL 1.1 | [Google Fonts](https://fonts.google.com/specimen/Big+Shoulders+Display), [repository](https://github.com/xotypeco/big_shoulders) | 214 KB (variable) |
| Courier Prime | Alan Dague-Greene | OFL 1.1 | [Google Fonts](https://fonts.google.com/specimen/Courier+Prime), [repository](https://github.com/quoteunquoteapps/CourierPrime) | 71 KB |
| Bowlby One | Vernon Adams | OFL 1.1 | [Google Fonts](https://fonts.google.com/specimen/Bowlby+One), [repository](https://github.com/googlefonts/bowlbyone) | 58 KB |
| Archivo | Omnibus-Type | OFL 1.1 | [Google Fonts](https://fonts.google.com/specimen/Archivo), [repository](https://github.com/Omnibus-Type/Archivo) | 643 KB (variable, width and weight) |
| League Gothic | Tyler Finck, Caroline Hadilaksono, Micah Rich | OFL 1.1 | [Google Fonts](https://fonts.google.com/specimen/League+Gothic), [repository](https://github.com/theleagueof/league-gothic) | 64 KB (variable width) |
| Special Elite | Astigmatic | Apache 2.0 | [Google Fonts](https://fonts.google.com/specimen/Special+Elite) | 162 KB |
| Fontdiner Swanky | Font Diner | Apache 2.0 | [Google Fonts](https://fonts.google.com/specimen/Fontdiner+Swanky), [repository](https://github.com/googlefonts/fontdinerswanky) | 44 KB |
| Libre Franklin | Impallari Type | OFL 1.1 | [Google Fonts](https://fonts.google.com/specimen/Libre+Franklin), [repository](https://github.com/googlefonts/Libre-Franklin) | 183 KB (variable) |

## Considered and left out

| Face | Why not |
| --- | --- |
| Atomic Age (OFL) | The G draws like a J: DEADNIGHT reads "DEADNIJHT". A title that misreads is a bug |
| Monoton (OFL) | A literal neon tube, a favourite of generated retro UI; its numerals are hard to read in the HUD |
| Limelight (OFL) | Art deco: a 1930s picture palace, not a 1958 drive-in |
| Alfa Slab One (OFL) | Heavy and legible, but a generic slab; nothing says drive-in |
| Inter, Poppins, Montserrat, Bebas Neue, Orbitron | The issue's avoid list; none used |

## Notes for the build

- **Latin only.** Bungee, Yellowtail, Fontdiner Swanky and Bowlby One cover Latin; a localised build needs a fallback
  face for other scripts. Barlow Condensed, Jost, Archivo and Libre Franklin cover Latin Extended and Vietnamese.
- **Variable fonts** (Jost, Big Shoulders, Archivo, League Gothic, Libre Franklin) work in Godot through
  `FontVariation.variation_opentype`, as the specimen does; a static weight is smaller and safer for the web export,
  so ship the static instances we use.
- **Inline faces need size.** Bungee Inline's inline stroke fills in at small sizes; use it for the title and big
  numbers only, and plain Bungee (OFL, 116 KB) or Barlow below that.
- **Web budget.** Pairing 1 as static files is about 250 KB (Bungee Inline plus two Barlow weights).
- `UITokens` has the slots `font_display`, `font_text` and `font_mono`; `UIThemeBuilder` applies them (display face to
  the display and title styles, text face to everything else, mono to `UILabelMono`), the neon sign takes the display
  slot, and a glyph a chosen face lacks falls back to the engine's font.

## Recommendation

**Marquee (Bungee Inline + Barlow Condensed)**, with **Yellowtail kept as an optional accent** for the lit sign on the
title card.

- It is the only pairing where both faces descend from signage, which is the game's world (neon, marquee, a lot of
  parked cars in the dark); the inline letters carry the marquee on their own, with no effect needed.
- Barlow Condensed does the work that decides a UI: menus, HUD, captions and numbers, in many static weights, tight
  and clear at menu size.
- Both are OFL: no notices beyond the licence text.
- Runner-up: **Ticket stub** (Big Shoulders + Courier Prime), the better choice if the UI should feel printed rather
  than lit. **B-movie poster** has the loudest title if we want it louder.

The comparison sheet is attached to the pull request; the maintainer's pick closes issue #11.

## Decision

The maintainer asked for the open-licence pair that best matches the game, starting from the recommendation and
checking it on the game's own screens. Captures of the real main menu, settings and HUD at 1280 x 720, 844 x 390 and
932 x 430 (true window pixels, `game/tests/captures/menu_fonts.tscn`), with the three finalists:

| Pair | Sign (the neon tube outline of each letter) | Menu, settings, HUD text | Verdict |
| --- | --- | --- | --- |
| **Bungee Inline + Barlow Condensed SemiBold** | The inline cut makes a double channel, so the tube reads as a lit marquee letter; 9 letters, G and I clear | Tall and narrow: "Open the concession stand" is one line in the HUD card | **Chosen** |
| Big Shoulders + Courier Prime Bold | A thin single tube, elegant more than loud, narrow | Courier is wide and light: HUD numbers go thin on the player rows, the prompt wraps | Rejected: not lit, and weak small |
| Bowlby One + Archivo (width 75) | A fat blob: the glyph outline fills solid, no tube is visible | Archivo wraps "Open the concession stand" onto two lines in the same card | Rejected: the neon effect is lost |

- **Bungee Inline is for the sign, display and title type only** (`UILabelDisplay`, `UILabelTitle`, the HUD's big
  numerals). Headings, buttons, captions and the settings use Barlow Condensed: the inline stroke fills in below about
  40 px on screen, and at the 40 px of the Settings title it already reads as a plain heavy face, which is acceptable
  there.
- **Barlow Condensed reads smaller than the engine's Open Sans at the same size**, so the game's tokens raise the scale
  (heading 38 to 44, body 26 to 32, button 28 to 34, caption 20 to 26, overline 18 to 26) and set the synthetic weight
  to 0.1 (the faces are already bold, and 0.5 filled the inline). The HUD's own sizes are unchanged.
- **Footer** (the line over the parked cars): caption size at full ink on a plate of the surface colour at 78 percent.
  At 720p the type went from 13 px to 17 px high and the contrast went from about 6:1 to about 15:1 (measured on the
  captures); a test holds at least 7:1 against the lightest possible ground (`test_menu_type.gd`).
- **Credits** list both faces and the engine's Open Sans (SIL OFL 1.1, still the fallback for a missing glyph); the
  names went to caption size so the list still fits one 1080-unit canvas.
- **Web budget.** The two imported font files add 60 KB (Barlow) and 87 KB (Bungee Inline) to the pack; one Barlow
  weight is used, the other weights stay out.
- **Phone landscape** (932 x 430, canvas scale 0.4): the sign, buttons and settings read; caption and HUD small text
  are about 10 px or less, a limit of the HUD's own sizes and the mobile plan, not of the face.

## Reproducing

The two chosen fonts are committed; the other candidates are not. To render a candidate, download its files into
`refs/fonts/<family>/` beside the repositories, then run the specimen scene with Movie Maker (or the real screens with
`menu_fonts.tscn`, whose `--face=pair:<id>` loads a pairing from that folder):

```text
godot --path game res://ui/specimens/typography_specimen.tscn --write-movie <out>.png --fixed-fps 10 --quit-after 3 -- --pairing=<id> --fonts=<fonts folder>
```

Ids: `marquee`, `neon-script`, `ticket`, `b-movie`, `gothic`, `diner` (and the rejected `atomic`, `tube`, `deco`,
`slab`). Pairings live in `game/ui/specimens/typography_pairings.gd`.
