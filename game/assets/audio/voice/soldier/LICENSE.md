# The soldier's voice, generated with ElevenLabs text to speech

- Source: ElevenLabs Text to Speech API (`POST /v1/text-to-speech/{voice_id}`, free tier), generated 2026-11-01 by
  `tools/audio/elevenlabs_voice.py` from the lines in `tools/audio/soldier_voice.json`. Every file's text, model,
  voice, settings, seed, length and characters are in `manifest.json`.
- Model `eleven_v4`; voice **Brian**, an ElevenLabs premade voice (`nPczCjzI2devNBz1zQrb`); settings stability 0.0,
  similarity boost 0.8, style 0.6; output `mp3_44100_128`, then trimmed, levelled to -20 LUFS and encoded to Ogg
  Vorbis by the same script. The lines are original, written for Deadnight.
- Two takes (`round_clear_1`, `streak_1`) are the samples the maintainer listened to and approved on 2026-11-01;
  the other 113 were requested once each.
- Licence: **generated with ElevenLabs (free tier); attribution required; not licensed for commercial use; replace or
  relicense before any commercial release.** Tracking issue for the relicensing: #252. The premade voice is
  ElevenLabs'; no custom or cloned voice is used.
- Decision: the maintainer chose the voice, the settings and "use it now, credit it" on 2026-11-01
  (issue #384, #252); the credit is on the Credits screen.

## Progression lines, added 2026-11-04 (issue #1063): FREE TIER, regenerate before release

- Source: the same ElevenLabs Text to Speech API and recipe (`tools/audio/elevenlabs_voice.py`), the lines in `tools/audio/soldier_voice.json`
  (the `level_up`, `tier_up`, `unlock`, `challenge_done`, `poster_set`, `card`, `emblem` and `first_game` events). Each
  take was requested once with the prompt below and the voice, model and settings above (voice **Brian**, `nPczCjzI2devNBz1zQrb`).
- **Plan that made them: `free`** (the subscription endpoint read `tier: free` before and after the requests). Each of
  the 24 files carries `"plan": "free"` and `"generated": "2026-11-04"` in `manifest.json`, which is the list
  #252 regenerates from. The maintainer, 2026-11-04: "Even with no commercial rights go ahead and get them going I'll get
  the package with commercial rights in a moment." **These files are not licensed for commercial use: regenerate them
  under the commercial plan (the same `generate` and `encode` commands with `--plan <plan>`) before any release.**
- The prompt of each take is its line (audio tags in brackets are performed, not spoken; the text in `manifest.json` is
  what was sent), 1018 characters written:
    - `level_up_1.ogg`: [excited] Level up! Now we're cooking! (38 characters, seed 2074)
    - `level_up_2.ogg`: [grinning] Climbing the ladder, one rung at a time! (51 characters, seed 2075)
    - `level_up_3.ogg`: [laughs] Moving up in the world, folks! (39 characters, seed 2076)
    - `tier_up_1.ogg`: [shouting, triumphant] New rank! Hear that brass?! (50 characters, seed 2077)
    - `tier_up_2.ogg`: [whooping] Whoo! Straight up the chain of command! (50 characters, seed 2078)
    - `tier_up_3.ogg`: [proud] Look at me. Stripes and everything. (43 characters, seed 2079)
    - `unlock_1.ogg`: [pleased] Ooh, something new. Don't mind if I do. (49 characters, seed 2080)
    - `unlock_2.ogg`: [excited] Look what I just earned! (34 characters, seed 2081)
    - `unlock_3.ogg`: [grins] Well, well. Look what I found. (38 characters, seed 2082)
    - `challenge_done_1.ogg`: [laughs] Ha! Nailed it. Put it on the board! (44 characters, seed 2083)
    - `challenge_done_2.ogg`: [smug] Challenge done. Easy as pie. (35 characters, seed 2084)
    - `challenge_done_3.ogg`: [chuckles] Scratch that one off the list. (41 characters, seed 2085)
    - `poster_set_1.ogg`: [delighted] The whole set! Every poster on the wall! (52 characters, seed 2086)
    - `poster_set_2.ogg`: [proud] Full set. Hang 'em up, folks. (37 characters, seed 2087)
    - `poster_set_3.ogg`: [laughs] That's the last poster. Now it looks right. (52 characters, seed 2088)
    - `card_1.ogg`: [pleased] A new calling card. Classy. (37 characters, seed 2089)
    - `card_2.ogg`: [chuckles] Fresh card in the deck. Deal me in. (46 characters, seed 2090)
    - `card_3.ogg`: [excited] New card! Hand 'em out! (33 characters, seed 2091)
    - `emblem_1.ogg`: [proud] Got me a new emblem. Wear it loud. (42 characters, seed 2092)
    - `emblem_2.ogg`: [grinning] Shiny new badge. Look at that shine. (47 characters, seed 2093)
    - `emblem_3.ogg`: [pleased] Fancy frame, fancy me. (32 characters, seed 2094)
    - `first_game_1.ogg`: [cheerful] First feature of the day. Let's go! (46 characters, seed 2095)
    - `first_game_2.ogg`: [upbeat] Doors are open. First show's on me. (44 characters, seed 2096)
    - `first_game_3.ogg`: [laughs] Day's first game. Bonus time! (38 characters, seed 2097)
